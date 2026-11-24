#!/usr/bin/env bash
# =====================================================================================
#  it505_aws.sh — the IT 505 lab in AWS Academy, driven from AWS CloudShell
#  IT 505 · Fundamentals of Database Technologies · Cyber.SoHo Educational Hub
#  Version 1.0 (21 November 2026)
#
#  Where to run it: in AWS CloudShell, inside the AWS console that the course
#  "AWS Academy Learner Lab" opens for you. Upload IT505_AWS_Kit.zip, unzip it, then:
#
#      bash it505_aws.sh check             who am I, which Region, what exists already
#
#  Part A — managed services (the database is run for you by AWS)
#      bash it505_aws.sh services-up       PostgreSQL on Amazon RDS + a DynamoDB table + an S3 bucket (+ Athena, Glue)
#      bash it505_aws.sh services-status   addresses and passwords
#      bash it505_aws.sh services-down     delete all of it, which also ends its cost
#
#  Part B — the cloud twin of your virtual machine (one Amazon EC2 instance, built by it505_setup.sh)
#      bash it505_aws.sh deploy            create the machine and install the whole toolbox (about 12 minutes)
#                                          options: --size medium|large   --desktop   --restore FILE
#      bash it505_aws.sh status            state, current public address, how to connect
#      bash it505_aws.sh start | stop      after a new lab session | before you leave
#      bash it505_aws.sh myip [ADDRESS]    your own internet address changed (home, campus)
#      bash it505_aws.sh ssh               a terminal on the machine
#      bash it505_aws.sh backup            databases + course folder -> one file in CloudShell, ready to download
#      bash it505_aws.sh restore FILE      load a backup file into the machine
#      bash it505_aws.sh rebuild [FILE]    start again from nothing: after the lab account was reset or the budget ran out
#      bash it505_aws.sh destroy           delete the machine and everything that belongs to it
#
#  Nothing here creates IAM (Identity and Access Management) users or roles: the Learner Lab does not allow it.
#  Every tool is open-source software or a standard AWS service, and each can be replaced by another
#  suitable one if you can justify the choice.
#  Legal notice: https://cyber-soho.github.io/prevmon/00.01.%20cyber.soho%20-%20legal.html
# =====================================================================================

# Stop on the use of an unset variable, and let a pipeline fail when any of its parts fails.
set -u -o pipefail

# ---- names used for everything this script creates, so that it can find its own resources again ----
NAME_TAG="it505-lab"                 # the Name tag of the EC2 instance
SG_NAME="it505-lab-sg"               # the security group (the firewall of the instance)
KEY_NAME="it505-key"                 # the key pair used for SSH (Secure Shell)
STACK="it505-services"               # the CloudFormation stack of Part A
# ---- where this script keeps its own files inside CloudShell ----
STATE_DIR="${IT505_STATE_DIR:-$HOME/.it505}"          # key file, passwords, remembered addresses
BACKUP_DIR="${IT505_BACKUP_DIR:-$HOME/it505-backups}" # backup files, ready to download
# The private half of the key pair, kept in the state folder.
PEM="$STATE_DIR/$KEY_NAME.pem"
# The folder this script lies in; the installer and the template are expected next to it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The installer of Guide 3, expected beside this script.
SETUP_SCRIPT="$HERE/it505_setup.sh"
# The description of the managed services, expected beside this script.
TEMPLATE="$HERE/it505_managed_services.yaml"
# The Region: CloudShell sets AWS_REGION; the Learner Lab allows us-east-1 and us-west-2.
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
# The account that publishes the official Debian images on AWS (wiki.debian.org/Cloud/AmazonEC2Image).
DEBIAN_OWNER="136693071363"

# ---- colours, only when the output is a terminal ----
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'; else G=""; R=""; Y=""; B=""; N=""; fi
# Print one line of text.
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s  ok  %s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s note %s %s\n' "$Y" "$N" "$*"; }
# Print a red stop line and end the script with an error.
die()  { printf '%s stop %s %s\n' "$R" "$N" "$*" >&2; exit 1; }
# Print the title of a step in bold type.
step() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
# Every AWS call names the Region explicitly, so that nothing is created in the wrong place.
a() { aws --region "$REGION" "$@"; }
# Produce a random password of 16 letters and digits.
random_password() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16; }
# Is this text an IPv4 address such as 203.0.113.7 ?
is_ipv4() { printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }

# Create the state folder and the backup folder; only you may read the state folder, because it holds passwords and the key.
mkdir -p "$STATE_DIR" "$BACKUP_DIR"; chmod 700 "$STATE_DIR"

# -------------------------------------------------------------------------------------
#  Checks shared by all commands
# -------------------------------------------------------------------------------------
preflight() {
  # This script needs the AWS command line, which CloudShell provides.
  command -v aws >/dev/null 2>&1 || die "The program 'aws' is missing. Run this script in AWS CloudShell."
  # Ask AWS who we are; this fails when the lab session has ended.
  ACCOUNT="$(a sts get-caller-identity --query Account --output text 2>/dev/null)" || die "AWS does not answer. Start the lab (Start Lab, wait for the green dot), open the AWS console from it, and open CloudShell again."
  # Warn if the Region is not one of the two that the Learner Lab allows.
  case "$REGION" in us-east-1|us-west-2) ;; *) warn "Region $REGION: the Learner Lab allows only us-east-1 and us-west-2." ;; esac
}

# The default network of the account and its subnets; the Learner Lab provides them.
find_network() {
  # Find the default network (VPC) of the account.
  VPC="$(a ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
  # Stop if the account has none.
  [ -n "$VPC" ] && [ "$VPC" != "None" ] || die "This account has no default network (VPC) in $REGION."
  # List the subnets of that network.
  SUBNETS="$(a ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId' --output text | tr '\t' ' ')"
  # Stop if there is none.
  [ -n "$SUBNETS" ] || die "The default network has no subnets."
}

# Your own public internet address, the only one allowed to reach the lab from outside AWS.
# Order: an address given on the command line, the variable IT505_MY_IP, the remembered one, a question.
student_ip() {
  # The address given as an argument, or by the variable IT505_MY_IP.
  local given="${1:-${IT505_MY_IP:-}}"
  # Otherwise the address remembered from the last run.
  if [ -z "$given" ] && [ -s "$STATE_DIR/my_ip" ]; then given="$(cat "$STATE_DIR/my_ip")"; fi
  # Ask until the answer looks like an address, or is the word any.
  while ! is_ipv4 "$given" && [ "$given" != "any" ]; do
    # Explain why the address is needed.
    say "${B}Your public internet address is needed.${N} Only this address will be allowed to reach your lab."
    say "Open  https://checkip.amazonaws.com  in a new browser tab and type the number shown there (for example 203.0.113.7)."
    # Read the answer from the keyboard.
    read -r -p "Your address: " given || die "No address given."
  done
  # Remember the address for the next run.
  printf '%s\n' "$given" >"$STATE_DIR/my_ip"
  # The word any opens the lab to every address: allowed, with a warning.
  if [ "$given" = "any" ]; then MY_CIDR="0.0.0.0/0"; warn "'any' opens the lab to the whole internet. Passwords and encryption still protect it, but an address of your own is safer."
  # A single address is written with the ending /32.
  else MY_CIDR="$given/32"; fi
}

# -------------------------------------------------------------------------------------
#  Part B helpers — the EC2 instance
# -------------------------------------------------------------------------------------
# Find the instance by its Name tag; sets INSTANCE, STATE_NAME, PUBLIC_IP, ITYPE (empty when there is none).
find_instance() {
  # One line of text will hold the facts about the machine.
  local line
  # Ask EC2 for the machine that carries the name tag of the kit and is not terminated.
  line="$(a ec2 describe-instances --filters "Name=tag:Name,Values=$NAME_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
          --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,InstanceType]' --output text 2>/dev/null | head -n 1)"
  # Split the answer into the identifier and the state of the machine.
  INSTANCE="$(printf '%s' "$line" | awk '{print $1}')"; STATE_NAME="$(printf '%s' "$line" | awk '{print $2}')"
  # And into its public address and its size.
  PUBLIC_IP="$(printf '%s' "$line" | awk '{print $3}')"; ITYPE="$(printf '%s' "$line" | awk '{print $4}')"
  # A stopped machine has no public address.
  [ "$PUBLIC_IP" = "None" ] && PUBLIC_IP=""
  # Finding no machine is not an error.
  return 0
}

# Find or create the security group; sets SG.
ensure_security_group() {
  # The security group lives in the default network.
  find_network
  # Look for the security group of the kit.
  SG="$(a ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)"
  # Create it if it does not exist.
  if [ -z "$SG" ] || [ "$SG" = "None" ]; then
    # A security group is the firewall that AWS puts around a machine.
    SG="$(a ec2 create-security-group --group-name "$SG_NAME" --description "IT 505 lab machine" --vpc-id "$VPC" --query GroupId --output text)" || die "The security group could not be created."
    # Confirm the creation.
    ok "security group $SG created"
  fi
}

# Remove every incoming rule of the security group whose description is $1.
revoke_rules() {
  # The identifiers of the rules to remove.
  local ids
  # Find the incoming rules that carry the given description.
  ids="$(a ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG" --query "SecurityGroupRules[?Description=='$1' && IsEgress==\`false\`].SecurityGroupRuleId" --output text 2>/dev/null | tr '\t' ' ')"
  # shellcheck disable=SC2086
  [ -n "$ids" ] && a ec2 revoke-security-group-ingress --group-id "$SG" --security-group-rule-ids $ids >/dev/null 2>&1
  # Having nothing to remove is not an error.
  return 0
}
# Allow one TCP port from one address range, with a description that says whose rule it is.
allow_port() {
  # Add one incoming rule: this port, from this address range, with this description.
  a ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions "IpProtocol=tcp,FromPort=$1,ToPort=$1,IpRanges=[{CidrIp=$2,Description=$3}]" >/dev/null 2>&1 || true
}
# The address CloudShell itself uses changes between sessions; allow the current one to use SSH.
allow_cloudshell() {
  # Ask a service of AWS for the public address of this CloudShell.
  local ip; ip="$(curl -s --max-time 8 https://checkip.amazonaws.com | tr -d '[:space:]')"
  # Without that address no rule can be written: warn and go on.
  is_ipv4 "$ip" || { warn "The address of CloudShell could not be determined; SSH from here may be refused."; return 0; }
  # Replace the old CloudShell rule with one for the current address, for port 22 (SSH).
  revoke_rules "it505-cloudshell"; allow_port 22 "$ip/32" "it505-cloudshell"
}
# Allow your own computer: SSH (22), JupyterLab (8888), PostgreSQL (5432), and the remote desktop (3389) when it was installed.
allow_student() {
  # Remove the rules of the previous student address.
  revoke_rules "it505-student"
  # Open SSH (22), JupyterLab (8888) and PostgreSQL (5432) for the address of the student.
  local p; for p in 22 8888 5432; do allow_port "$p" "$MY_CIDR" "it505-student"; done
  # With the desktop option, open the remote-desktop port 3389 as well.
  if grep -qs '^DESKTOP=1' "$STATE_DIR/twin.env"; then allow_port 3389 "$MY_CIDR" "it505-student"; fi
}

# Find or create the key pair; the private half stays in this CloudShell only.
ensure_key() {
  # Does AWS know a key pair with the name of the kit?
  local exists; exists="$(a ec2 describe-key-pairs --key-names "$KEY_NAME" --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || true)"
  # If AWS knows it and the private file is here, nothing has to be done.
  if [ "$exists" = "$KEY_NAME" ] && [ -s "$PEM" ]; then return 0; fi
  # A key pair without its private file is useless: remove it and make a new one.
  [ "$exists" = "$KEY_NAME" ] && a ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1
  # Create a new key pair: AWS keeps the public half, the private half goes into a file that only you can read.
  ( umask 077; a ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 --query KeyMaterial --output text >"$PEM" ) || die "The key pair could not be created."
  # Protect the file, forget the host keys of earlier machines, and confirm.
  chmod 600 "$PEM"; rm -f "$STATE_DIR/known_hosts"; ok "key pair $KEY_NAME created (private file: $PEM)"
}

# Choose the machine image: Debian 13 first, Ubuntu 24.04 as the alternative. Sets AMI, OS_USER, OS_LABEL.
find_image() {
  # The wanted system: debian unless ubuntu was asked for.
  local want="${1:-debian}"
  # No image found yet.
  AMI=""
  # A fixed image can be forced with the variables IT505_AMI and IT505_OS_USER (the login name of that image).
  if [ -n "${IT505_AMI:-}" ]; then AMI="$IT505_AMI"; OS_USER="${IT505_OS_USER:-admin}"; OS_LABEL="chosen system"; return 0; fi
  # For Debian there are two ways to find the newest official image.
  if [ "$want" = "debian" ]; then
    # The Debian project publishes the newest image identifiers as public parameters; ask for the amd64 one.
    AMI="$(a ssm get-parameters-by-path --recursive --path /aws/service/debian/release/13/latest --query "Parameters[?ends_with(Name, '/amd64')].Value | [0]" --output text 2>/dev/null || true)"
    # Second way: list the images of the Debian account and take the newest.
    if [ -z "$AMI" ] || [ "$AMI" = "None" ]; then
      # Take the newest available image whose name begins with debian-13-amd64.
      AMI="$(a ec2 describe-images --owners "$DEBIAN_OWNER" --filters "Name=name,Values=debian-13-amd64-*" "Name=state,Values=available" --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text 2>/dev/null || true)"
    fi
    # Login name and label of the Debian image.
    OS_USER="admin"; OS_LABEL="Debian 13"
  else
    # Canonical publishes its Ubuntu images the same way.
    AMI="$(a ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text 2>/dev/null || true)"
    # Login name and label of the Ubuntu image.
    OS_USER="ubuntu"; OS_LABEL="Ubuntu 24.04"
  fi
  # Succeed only if an image was found.
  [ -n "$AMI" ] && [ "$AMI" != "None" ]
}

# Options shared by every ssh and scp call. HostKeyAlias makes the machine recognisable although its address changes.
SSH_OPTS=(-i "$PEM" -o HostKeyAlias="$NAME_TAG" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$STATE_DIR/known_hosts" -o ConnectTimeout=10 -o ServerAliveInterval=30 -o LogLevel=ERROR)
# Run a command on the lab machine through SSH.
remote()  { ssh "${SSH_OPTS[@]}" "$OS_USER@$PUBLIC_IP" "$@"; }
# Load what an earlier "deploy" remembered: the login name of the image and the passwords.
load_twin_env() { OS_USER="admin"; [ -s "$STATE_DIR/twin.env" ] && . "$STATE_DIR/twin.env"; return 0; }

# Make sure the instance exists, runs, and answers to SSH from this CloudShell.
need_running_instance() {
  # Find the machine and read the saved settings.
  find_instance; load_twin_env
  # Stop if there is no machine.
  [ -n "$INSTANCE" ] || die "There is no lab machine yet. Create it with: bash it505_aws.sh deploy"
  # Stop if it is not running.
  [ "$STATE_NAME" = "running" ] || die "The machine is $STATE_NAME. Start it with: bash it505_aws.sh start"
  # Stop if the private key is not in this CloudShell.
  [ -s "$PEM" ] || die "The key file $PEM is missing in this CloudShell (CloudShell storage was reset). Use: bash it505_aws.sh rebuild"
  # Make sure that this CloudShell may reach the machine.
  ensure_security_group; allow_cloudshell
  # Wait up to three minutes until the machine answers.
  for _ in $(seq 1 30); do remote true 2>/dev/null && return 0; sleep 6; done
  # It did not answer: stop with advice.
  die "The machine does not answer to SSH. Wait a minute and try again; 'bash it505_aws.sh status' shows its state."
}

print_access() {
  # Find the machine and read the saved settings.
  find_instance; load_twin_env
  # An empty line before the card.
  say ""
  say "${B}Your IT 505 cloud machine${N}  ($INSTANCE, $ITYPE, ${OS_LABEL:-Debian 13}, $REGION)"
  say "  State          : $STATE_NAME"
  # A running machine: show how to reach each service.
  if [ "$STATE_NAME" = "running" ] && [ -n "$PUBLIC_IP" ]; then
    # First its public address.
    say "  Public address : $PUBLIC_IP   (it changes every time the machine is started)"
    say "  JupyterLab     : https://$PUBLIC_IP:8888     password: ${JUPYTER_PASSWORD:-see ~/it505/ACCESS.txt on the machine}"
    say "                   the browser warns about the certificate once: Advanced > Proceed"
    say "  PostgreSQL     : host $PUBLIC_IP  port 5432  database mercadillo  user it505  password: ${PG_PASSWORD:-see ACCESS.txt}"
    # With the desktop option: the remote-desktop address.
    grep -qs '^DESKTOP=1' "$STATE_DIR/twin.env" && say "  Remote desktop : $PUBLIC_IP port 3389   user $OS_USER   password: the PostgreSQL password"
    # How to open a terminal, and from which address the machine can be reached.
    say "  Terminal       : bash it505_aws.sh ssh"
    say "  Allowed from   : $(cat "$STATE_DIR/my_ip" 2>/dev/null || echo 'not set — run: bash it505_aws.sh myip')"
  else
    # A stopped machine: say how to start it.
    say "  Start it with  : bash it505_aws.sh start"
  fi
}

# -------------------------------------------------------------------------------------
#  Part B commands
# -------------------------------------------------------------------------------------
cmd_deploy() {
  # The defaults: medium size, no desktop, nothing to restore, Debian.
  local size="medium" desktop=0 restore_file="" os="debian"
  # Read the options.
  while [ $# -gt 0 ]; do
    case "$1" in
      --size) size="${2:-medium}"; shift ;;   # small, medium or large
      --desktop) desktop=1 ;;   # add a remote desktop
      --restore) restore_file="${2:-}"; shift ;;   # a backup file to load into the new machine
      --os) os="${2:-debian}"; shift ;;   # debian or ubuntu
      *) die "Unknown option for deploy: $1" ;;   # anything else is a mistake
    # Go on to the next word.
    esac; shift
  done
  # Only the three sizes that the Learner Lab allows.
  case "$size" in small|medium|large) ;; *) die "--size must be small, medium or large (the Learner Lab allows nothing bigger)." ;; esac
  # The installer must lie beside this script.
  [ -r "$SETUP_SCRIPT" ] || die "it505_setup.sh must lie next to this script (it is part of IT505_AWS_Kit.zip)."
  # A backup file that was named must exist.
  [ -z "$restore_file" ] || [ -r "$restore_file" ] || die "Backup file not found: $restore_file"
  # Check the account and look for an existing machine.
  preflight; find_instance
  # Never create a second machine.
  [ -z "$INSTANCE" ] || die "A lab machine exists already ($INSTANCE, $STATE_NAME). Use 'status', or 'rebuild' to start again from nothing."

  # Step 1: say what is about to happen.
  step "1/6  Your internet address"
  # Ask for the address of the student and confirm it.
  student_ip ""; ok "the lab will accept connections from $MY_CIDR"

  # Step 2: say what is about to happen.
  step "2/6  Key pair and security group"
  # Create the key pair and the security group if they are missing.
  ensure_key; ensure_security_group
  # Passwords of this machine: made here, kept in a file that only you can read.
  PG_PASSWORD="$(random_password)"; JUPYTER_PASSWORD="$(random_password)"
  # Save the passwords and the desktop choice in a file that only you can read.
  ( umask 077; printf 'PG_PASSWORD=%s\nJUPYTER_PASSWORD=%s\nDESKTOP=%s\n' "$PG_PASSWORD" "$JUPYTER_PASSWORD" "$desktop" >"$STATE_DIR/twin.env" )
  # Open the ports for this CloudShell and for the student, and confirm.
  allow_cloudshell; allow_student; ok "security group $SG: SSH, JupyterLab and PostgreSQL from your address only"

  # Step 3: say what is about to happen.
  step "3/6  Machine image"
  # Find the image; if the wanted system has none, try Ubuntu.
  if ! find_image "$os"; then warn "No $os image found; trying Ubuntu 24.04."; find_image ubuntu || die "No machine image could be found."; fi
  # The name of the system disk inside that image; the disk size is set under this name.
  local rootdev; rootdev="$(a ec2 describe-images --image-ids "$AMI" --query 'Images[0].RootDeviceName' --output text)"
  # Confirm the image and its login name.
  ok "$OS_LABEL image $AMI (login name: $OS_USER)"

  # Step 4: say what is about to happen.
  step "4/6  Start the instance (t3.$size, 30 GB disk)"
  # The first subnet of the default network.
  local subnet; subnet="$(printf '%s' "$SUBNETS" | awk '{print $1}')"
  # The common part of the request: image, size, key, firewall, disk, and a Name tag to find it again.
  local args=(--image-id "$AMI" --instance-type "t3.$size" --key-name "$KEY_NAME" --security-group-ids "$SG" --subnet-id "$subnet"
              # A system disk of 30 GB of the type gp3, deleted together with the machine.
              --block-device-mappings "DeviceName=$rootdev,Ebs={VolumeSize=30,VolumeType=gp3,DeleteOnTermination=true}"
              # Require the newer, safer way for programs on the machine to ask AWS about the machine itself.
              --metadata-options "HttpTokens=required,HttpEndpoint=enabled"
              # Tags: the name by which this script finds the machine again, and the course.
              --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG},{Key=Course,Value=IT505}]" "ResourceType=volume,Tags=[{Key=Name,Value=$NAME_TAG}]"
              # Return only the identifier of the new machine.
              --query 'Instances[0].InstanceId' --output text)
  # LabInstanceProfile is the ready-made permission set of the Learner Lab; if it is absent, start without it.
  INSTANCE="$(a ec2 run-instances "${args[@]}" --iam-instance-profile Name=LabInstanceProfile 2>/dev/null)" || INSTANCE="$(a ec2 run-instances "${args[@]}" 2>"$STATE_DIR/run.err")" || {
    # If the Debian image is refused in this lab, try once more with Ubuntu.
    if [ "$OS_LABEL" = "Debian 13" ] && find_image ubuntu; then
      # Say why Debian was refused and which system is tried instead.
      warn "The Debian image was refused ($(head -c 160 "$STATE_DIR/run.err")). Trying $OS_LABEL."
      # The name of the system disk of the Ubuntu image.
      rootdev="$(a ec2 describe-images --image-ids "$AMI" --query 'Images[0].RootDeviceName' --output text)"
      # Put the new image and its disk name into the prepared request.
      args[1]="$AMI"; args[11]="DeviceName=$rootdev,Ebs={VolumeSize=30,VolumeType=gp3,DeleteOnTermination=true}"
      # Second attempt; stop if it fails too.
      INSTANCE="$(a ec2 run-instances "${args[@]}" 2>"$STATE_DIR/run.err")" || die "The instance could not be started: $(head -c 300 "$STATE_DIR/run.err")"
    # No other system is left to try: stop with the reason.
    else die "The instance could not be started: $(head -c 300 "$STATE_DIR/run.err")"; fi
  }
  # Remember the login name and the label of the system.
  printf 'OS_USER=%s\nOS_LABEL="%s"\n' "$OS_USER" "$OS_LABEL" >>"$STATE_DIR/twin.env"
  # Wait until the machine runs, then read its address.
  a ec2 wait instance-running --instance-ids "$INSTANCE"; find_instance
  # Confirm.
  ok "instance $INSTANCE is running at $PUBLIC_IP"

  # Step 5: say what is about to happen.
  step "5/6  Install the toolbox on the machine (about 10 minutes)"
  # A new machine has a new host key: forget the old ones.
  rm -f "$STATE_DIR/known_hosts"
  # Wait up to four minutes until SSH answers.
  for _ in $(seq 1 40); do remote true 2>/dev/null && break; sleep 6; done
  # Still no answer: stop with advice on how to continue later.
  remote true 2>/dev/null || die "The machine does not answer to SSH yet. Run 'bash it505_aws.sh status' in a minute, then 'bash it505_aws.sh install'."
  # Copy the installer to the machine and run it.
  run_installer "$desktop"

  # Step 6: say what is about to happen.
  step "6/6  Result"
  # Load the backup if one was named.
  if [ -n "$restore_file" ]; then cmd_restore "$restore_file"; fi
  # Print the access card.
  print_access
  # An empty line, then the closing advice.
  say ""
  say "${B}Before you leave:${N} bash it505_aws.sh backup   (then download the file), and  bash it505_aws.sh stop"
}

# Copy the installer to the machine and run it there; the machine keeps working even if CloudShell disconnects.
run_installer() {
  # The desktop choice, and the extra option that it adds.
  local desktop="${1:-0}" extra=""
  # Read the saved passwords.
  load_twin_env
  # With the desktop choice, pass --desktop to the installer.
  [ "$desktop" = "1" ] && extra="--desktop"
  # The passwords travel in a file that only the login account can read; the installer deletes it after reading.
  ( umask 077; printf 'IT505_PG_PASSWORD=%s\nIT505_JUPYTER_PASSWORD=%s\n' "$PG_PASSWORD" "$JUPYTER_PASSWORD" >"$STATE_DIR/it505.env" )
  # Copy the installer and the password file to the machine.
  scp "${SSH_OPTS[@]}" -q "$SETUP_SCRIPT" "$STATE_DIR/it505.env" "$OS_USER@$PUBLIC_IP:" || die "The installer could not be copied to the machine."
  # Delete the local copy of the password file.
  rm -f "$STATE_DIR/it505.env"
  # nohup + & : the installer continues when this connection ends; its output goes to a file on the machine.
  remote "sudo rm -f /var/lib/it505/setup.done; nohup sudo bash ~/it505_setup.sh --profile cloud --env-file ~/it505.env --yes $extra > ~/it505-setup.out 2>&1 < /dev/null &" || die "The installer could not be started."
  # Show the new lines of that file every 10 seconds until the installer reports that it has finished.
  local seen=0 out total tries=0
  # Look every ten seconds, for at most 40 minutes.
  while [ "$tries" -lt 240 ]; do
    # Read the output so far, and a marker when the installer has finished.
    out="$(remote 'cat ~/it505-setup.out 2>/dev/null; test -f /var/lib/it505/setup.done && echo __IT505_DONE__' 2>/dev/null || true)"
    # Count the lines of output.
    total="$(printf '%s\n' "$out" | grep -vc '__IT505_DONE__' || true)"
    # Print only the lines that are new since the last look.
    if [ "$total" -gt "$seen" ]; then printf '%s\n' "$out" | grep -v '__IT505_DONE__' | sed -n "$((seen + 1)),${total}p" | sed 's/^/    /'; seen="$total"; fi
    # Leave the loop when the marker is there.
    printf '%s' "$out" | grep -q '__IT505_DONE__' && break
    # Otherwise wait ten seconds and look again.
    tries=$((tries + 1)); sleep 10
  done
  # The time is up: stop with advice.
  [ "$tries" -lt 240 ] || die "The installer did not finish within 40 minutes. Look at it with: bash it505_aws.sh ssh   then: tail ~/it505-setup.out"
  # Read the number of failed steps that the installer noted.
  local failed; failed="$(remote 'cat /var/lib/it505/setup.done' 2>/dev/null | tr -dc '0-9')"
  # Report the result.
  if [ "${failed:-1}" = "0" ]; then ok "the toolbox is installed"; else warn "${failed:-some} step(s) of the installer failed; run 'bash it505_aws.sh install' to repeat only those."; fi
}

# The command install: run the installer again on the existing machine, then print the access card.
cmd_install() { preflight; need_running_instance; run_installer "$(grep -qs '^DESKTOP=1' "$STATE_DIR/twin.env" && echo 1 || echo 0)"; print_access; }

cmd_status() {
  # Check the account and look for the machine.
  preflight; find_instance
  # No machine: say how to create one.
  if [ -z "$INSTANCE" ]; then say "There is no lab machine in $REGION. Create it with: bash it505_aws.sh deploy"
  # Otherwise print the access card.
  else print_access; fi
  # Part A, if its stack exists.
  local st; st="$(a cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)"
  # Mention the managed services if their stack exists.
  [ -n "$st" ] && [ "$st" != "None" ] && say "" && say "Managed services (stack $STACK): $st   — details: bash it505_aws.sh services-status"
  # This overview never fails.
  return 0
}

cmd_start() {
  # Check the account; stop if there is no machine.
  preflight; find_instance; [ -n "$INSTANCE" ] || die "There is no lab machine. Create it with: bash it505_aws.sh deploy"
  # Start the machine unless it runs already.
  if [ "$STATE_NAME" != "running" ]; then
    # Ask EC2 to start it.
    a ec2 start-instances --instance-ids "$INSTANCE" >/dev/null || die "The machine could not be started."
    # Wait until it runs.
    say "Starting $INSTANCE ..."; a ec2 wait instance-running --instance-ids "$INSTANCE"
  fi
  # The address of CloudShell may have changed too: renew its rule.
  ensure_security_group; allow_cloudshell
  # Print the access card with the new address.
  print_access
}

cmd_stop() {
  # Check the account; stop if there is no machine.
  preflight; find_instance; [ -n "$INSTANCE" ] || die "There is no lab machine."
  # Ask EC2 to stop it, and say what a stopped machine costs.
  a ec2 stop-instances --instance-ids "$INSTANCE" >/dev/null && ok "$INSTANCE is stopping. Its disk and your data are kept; a stopped machine costs only its disk (about 2.40 USD a month for 30 GB)."
}

cmd_myip() {
  # Forget the remembered address, ask for the new one, and replace the rules.
  preflight; ensure_security_group; rm -f "$STATE_DIR/my_ip"; student_ip "${1:-}"; allow_student
  # Confirm.
  ok "the lab now accepts connections from $MY_CIDR only"
}

# The command ssh: open an interactive terminal on the machine.
cmd_ssh() { preflight; need_running_instance; say "Connected to the lab machine. Type 'exit' to come back to CloudShell."; ssh "${SSH_OPTS[@]}" -t "$OS_USER@$PUBLIC_IP"; }

cmd_backup() {
  # The machine must be running.
  preflight; need_running_instance
  # Say what is about to happen.
  step "Backup of the lab machine"
  # Ask the machine to write a backup, then read back the name of the newest file.
  remote 'it505 backup ~/it505/backups' | sed 's/^/    /'
  # Ask the machine for the name of its newest backup file.
  local newest; newest="$(remote 'ls -t ~/it505/backups/it505-backup-*.tar.gz 2>/dev/null | head -n 1')"
  # Stop if it has none.
  [ -n "$newest" ] || die "The machine did not produce a backup file."
  # Copy that file into the backup folder of CloudShell.
  scp "${SSH_OPTS[@]}" -q "$OS_USER@$PUBLIC_IP:$newest" "$BACKUP_DIR/" || die "The backup file could not be copied to CloudShell."
  # The path of the copy.
  local file; file="$BACKUP_DIR/$(basename "$newest")"
  # Confirm with the size of the file.
  ok "backup copied to CloudShell: $file ($(du -h "$file" | cut -f1))"
  say ""
  say "${B}Now download it to your own computer${N} — the only place that survives a reset of the lab account:"
  say "  CloudShell menu  Actions > Download file  and paste this path:"
  say "  $file"
}

cmd_restore() {
  # The backup file named on the command line.
  local file="${1:-}"
  # Without a name: the newest backup in CloudShell.
  [ -n "$file" ] || file="$(ls -t "$BACKUP_DIR"/it505-backup-*.tar.gz 2>/dev/null | head -n 1 || true)"
  # Stop if no readable file was found.
  [ -r "$file" ] || die "Give a backup file: bash it505_aws.sh restore PATH   (upload it first with Actions > Upload file)"
  # The machine must be running.
  preflight; need_running_instance
  # Say what is about to happen.
  step "Restore $(basename "$file") into the lab machine"
  # Copy the backup file to the machine.
  scp "${SSH_OPTS[@]}" -q "$file" "$OS_USER@$PUBLIC_IP:/tmp/it505-restore.tar.gz" || die "The backup file could not be copied to the machine."
  # Restore it there, delete the copy, and show the output indented.
  remote 'it505 restore /tmp/it505-restore.tar.gz; rm -f /tmp/it505-restore.tar.gz' | sed 's/^/    /'
}

cmd_destroy() {
  # Check the account and look for the machine.
  preflight; find_instance
  # Say what is about to happen.
  step "Delete the lab machine and everything that belongs to it"
  # Delete the machine if there is one.
  if [ -n "$INSTANCE" ]; then
    # Ask EC2 to terminate it.
    a ec2 terminate-instances --instance-ids "$INSTANCE" >/dev/null && say "    terminating $INSTANCE ..."
    # Wait until it is gone.
    a ec2 wait instance-terminated --instance-ids "$INSTANCE" && ok "instance deleted (its disk is deleted with it)"
  # There was no machine to delete.
  else say "    no instance found"; fi
  # The security group can be deleted only after the instance has released it; try a few times.
  find_network
  # Look for the security group of the kit.
  local sg; sg="$(a ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  # Delete it if it exists.
  if [ -n "$sg" ] && [ "$sg" != "None" ]; then
    # The group can be deleted only when the machine is completely gone: try for half a minute.
    for _ in 1 2 3 4 5 6; do a ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 && { ok "security group deleted"; break; }; sleep 5; done
  fi
  # Delete the public half of the key pair at AWS.
  a ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1 && ok "key pair deleted"
  # Delete the private half, the remembered host keys and the saved passwords.
  rm -f "$PEM" "$STATE_DIR/known_hosts" "$STATE_DIR/twin.env"
  # Say what is deliberately kept.
  say "Backup files in $BACKUP_DIR are kept."
}

cmd_rebuild() {
  # The backup file named on the command line; medium size unless the old machine says otherwise.
  local file="${1:-}" size="medium"
  # Check the account and look for the machine.
  preflight; find_instance
  # Say what is about to happen.
  step "Rebuild the lab machine from nothing"
  # If a machine still exists and answers, save its current state first.
  if [ -n "$INSTANCE" ] && [ "$STATE_NAME" = "running" ] && [ -s "$PEM" ] && [ -z "$file" ]; then
    # Explain why a fresh backup is taken.
    say "A running machine was found: taking a fresh backup before it is deleted."
    # Take it in a sub-shell, so that a failure does not end the rebuild.
    ( cmd_backup ) || warn "No fresh backup could be taken; the newest file in $BACKUP_DIR will be used."
  fi
  # Without a named file: the newest backup in CloudShell.
  [ -n "$file" ] || file="$(ls -t "$BACKUP_DIR"/it505-backup-*.tar.gz 2>/dev/null | head -n 1 || true)"
  # Say which backup will be restored, or warn that there is none.
  if [ -n "$file" ]; then say "Backup that will be restored: $file"; else warn "No backup file found: the new machine will be empty. Upload one with Actions > Upload file, then: bash it505_aws.sh restore FILE"; fi
  # Keep the size of the old machine.
  [ -n "$INSTANCE" ] && { case "$ITYPE" in t3.large) size="large" ;; t3.small) size="small" ;; esac; }
  # Keep the desktop choice of the old machine.
  local desktop_opt=(); grep -qs '^DESKTOP=1' "$STATE_DIR/twin.env" && desktop_opt=(--desktop)
  # Delete the old machine, its security group and its key pair.
  ( cmd_destroy )
  # Create the new machine and load the backup, if there is one.
  if [ -n "$file" ]; then cmd_deploy --size "$size" "${desktop_opt[@]}" --restore "$file"; else cmd_deploy --size "$size" "${desktop_opt[@]}"; fi
}

# -------------------------------------------------------------------------------------
#  Part A commands — managed services through one CloudFormation stack
# -------------------------------------------------------------------------------------
# The names below are fixed in it505_managed_services.yaml. The script uses them when the stack does not report a value itself.
DB_ID="it505-postgres"; TABLE_NAME="it505-orders"; WORKGROUP="it505"

# State of the stack (for example CREATE_COMPLETE); empty when the stack does not exist.
stack_status() { local v; v="$(a cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)"; [ "$v" = "None" ] && v=""; printf '%s' "$v"; }

# One output value of the stack; empty when the stack does not report it.
stack_output() { local v; v="$(a cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text 2>/dev/null || true)"; [ "$v" = "None" ] && v=""; printf '%s' "$v"; }

# Name of the file bucket: from the stack, otherwise built the way the template builds it.
bucket_name() { local b; b="$(stack_output BucketName)"; printf '%s' "${b:-it505-data-$ACCOUNT-$REGION}"; }

# Address of the database server: from the stack, otherwise asked from Amazon RDS directly.
db_host() {
  # First ask the stack.
  local h; h="$(stack_output DbEndpoint)"
  # Otherwise ask Amazon RDS for the address of the database with the fixed name.
  if [ -z "$h" ]; then h="$(a rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || true)"; [ "$h" = "None" ] && h=""; fi
  # Print the address, or a note that the database is not ready.
  printf '%s' "${h:-(not ready yet)}"
}

# True when the Athena workgroup of the kit exists.
has_workgroup() { [ -n "$(stack_output AthenaWorkGroup)" ] || [ "$(a athena get-work-group --work-group "$WORKGROUP" --query 'WorkGroup.Name' --output text 2>/dev/null || true)" = "$WORKGROUP" ]; }

# Removes what an interrupted earlier attempt left behind, so that the fixed names of the template are free again.
clear_leftovers() {
  # The state of the stack decides what has to be cleared.
  local st; st="$(stack_status)"
  case "$st" in
    ROLLBACK_COMPLETE|ROLLBACK_FAILED|DELETE_FAILED)
      # Say what is being removed.
      say "    removing the remains of an earlier attempt (the stack is in the state $st) ..."
      # A bucket that still holds files cannot be deleted, so empty it first.
      a s3 rm "s3://$(bucket_name)" --recursive >/dev/null 2>&1 || true
      # Delete the stack and wait until it is gone.
      a cloudformation delete-stack --stack-name "$STACK" >/dev/null 2>&1 || true
      # Wait until the stack is gone.
      a cloudformation wait stack-delete-complete --stack-name "$STACK" 2>/dev/null || true
      # Ask again for the state of the stack.
      st="$(stack_status)" ;;
  esac
  # With no stack present, a database, table or bucket that still carries a name of the kit would block the new stack.
  [ -z "$st" ] || return 0
  # Is there a database with the name of the kit?
  if a rds describe-db-instances --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
    # Say that it is being deleted.
    say "    a database named $DB_ID still exists outside the stack; deleting it (a few minutes) ..."
    # --skip-final-snapshot: keep no copy, because a copy would go on costing money.
    a rds delete-db-instance --db-instance-identifier "$DB_ID" --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 || true
    # Wait until the database is gone.
    a rds wait db-instance-deleted --db-instance-identifier "$DB_ID" 2>/dev/null || true
  fi
  # Is there a table with the name of the kit?
  if a dynamodb describe-table --table-name "$TABLE_NAME" >/dev/null 2>&1; then
    # Say that it is being deleted.
    say "    a table named $TABLE_NAME still exists outside the stack; deleting it ..."
    # Delete the table.
    a dynamodb delete-table --table-name "$TABLE_NAME" >/dev/null 2>&1 || true
    # Wait until it is gone.
    a dynamodb wait table-not-exists --table-name "$TABLE_NAME" 2>/dev/null || true
  fi
  # Is there a bucket with the name of the kit?
  if a s3api head-bucket --bucket "$(bucket_name)" >/dev/null 2>&1; then
    # Say that it is being emptied and deleted.
    say "    the bucket $(bucket_name) still exists outside the stack; emptying and deleting it ..."
    # rb --force: remove every file in the bucket, then the bucket itself.
    a s3 rb "s3://$(bucket_name)" --force >/dev/null 2>&1 || true
  fi
}

cmd_services_up() {
  # The description of the services must lie beside this script.
  [ -r "$TEMPLATE" ] || die "it505_managed_services.yaml must lie next to this script (it is part of IT505_AWS_Kit.zip)."
  # Check the account, find the network, and ask for the address of the student.
  preflight; find_network; student_ip ""
  # The password of the RDS database: made once, kept in a file that only you can read.
  if [ ! -s "$STATE_DIR/services.env" ]; then ( umask 077; printf 'DB_PASSWORD=%s\n' "$(random_password)" >"$STATE_DIR/services.env" ); fi
  # Read the password.
  . "$STATE_DIR/services.env"
  # CloudFormation wants the subnets as one list separated by commas.
  local subnet_list; subnet_list="$(printf '%s' "$SUBNETS" | tr ' ' ',')"
  # A stack whose creation or deletion failed, or a resource that outlived its stack, must go before a new attempt can succeed.
  clear_leftovers
  # Phase 1: say what is about to happen.
  step "1/2  Relational, key-value and file storage: Amazon RDS for PostgreSQL, a DynamoDB table, an S3 bucket"
  # Prepare the user for the waiting time.
  say "    CloudFormation creates the resources; the database alone takes 6 to 10 minutes. Leave this window open."
  # Create or update the stack without the Athena part; the options hand over network, address and password.
  a cloudformation deploy --stack-name "$STACK" --template-file "$TEMPLATE" --no-fail-on-empty-changeset \
    --parameter-overrides "VpcId=$VPC" "SubnetIds=$subnet_list" "ClientCidr=$MY_CIDR" "DbPassword=$DB_PASSWORD" "WithAnalytics=false" \
    --tags Course=IT505 || die "The stack could not be created. Open CloudFormation in the console, choose $STACK > Events, and read the first line marked CREATE_FAILED."
  # Confirm phase 1.
  ok "core services are ready"
  # Phase 2: say what is about to happen.
  step "2/2  SQL on files: an Athena workgroup and a Glue database"
  # Update the stack with the Athena part; errors go into a file, because a refusal is an expected outcome in some labs.
  if a cloudformation deploy --stack-name "$STACK" --template-file "$TEMPLATE" --no-fail-on-empty-changeset \
       --parameter-overrides "VpcId=$VPC" "SubnetIds=$subnet_list" "ClientCidr=$MY_CIDR" "DbPassword=$DB_PASSWORD" "WithAnalytics=true" --tags Course=IT505 2>"$STATE_DIR/analytics.err"; then
    # Confirm phase 2.
    ok "Athena workgroup and Glue database are ready"
  else
    # Athena or Glue was refused: explain that the rest works, and name the alternative.
    warn "Athena or Glue is not available in this lab; CloudFormation put the stack back to its previous good state. The other services work. For Athena, use the lab 'Querying Data by Using Athena' of the course AWS Academy Data Engineering."
  fi
  # Print the addresses and the password.
  cmd_services_status
}

cmd_services_status() {
  # Check the account.
  preflight
  # The state of the stack.
  local st; st="$(stack_status)"
  # No stack: say how to create the services.
  if [ -z "$st" ]; then say "The managed services do not exist. Create them with: bash it505_aws.sh services-up"; return 0; fi
  # Read the password if this CloudShell still has it.
  [ -s "$STATE_DIR/services.env" ] && . "$STATE_DIR/services.env"
  # An empty line before the card.
  say ""
  say "${B}IT 505 managed services${N}  (stack $STACK: $st, Region $REGION)"
  say "  Relational  · Amazon RDS for PostgreSQL"
  # Port, database name and user are fixed in the template; the address of the server is known only once the database exists.
  local port; port="$(stack_output DbPort)"
  # The line that DBeaver or psql needs.
  say "      host $(db_host)   port ${port:-5432}   database mercadillo   user it505   password ${DB_PASSWORD:-(in the CloudShell where the stack was created)}"
  say "      connect with DBeaver or psql from your virtual machine; the connection is encrypted with TLS"
  say "  Key-value   · Amazon DynamoDB table  $TABLE_NAME   (keys: pk, sk)"
  say "  Flat files  · Amazon S3 bucket       $(bucket_name)"
  # Athena exists: show the names of its workgroup and database.
  if has_workgroup; then say "  SQL on files· Amazon Athena workgroup $WORKGROUP, Glue database it505   (each query may read at most 1 GB)"
  # Athena was not created in this lab.
  else say "  SQL on files· not created in this lab (see the note printed by services-up)"; fi
  # The address that may reach the services.
  say "  Allowed from: $(cat "$STATE_DIR/my_ip" 2>/dev/null || echo unknown)"
  say ""
  say "${Y}The RDS database costs money every hour that it exists, also after the lab session ends.${N} When the exercise is done: bash it505_aws.sh services-down"
}

cmd_services_down() {
  # Check the account.
  preflight
  # Say what is about to happen.
  step "Delete the managed services"
  # No stack: nothing to delete.
  if [ -z "$(stack_status)" ]; then say "The managed services do not exist; nothing to delete."; rm -f "$STATE_DIR/services.env"; return 0; fi
  # The name of the bucket.
  local bucket; bucket="$(bucket_name)"
  # CloudFormation refuses to delete a bucket that still holds files, so empty it first.
  a s3 rm "s3://$bucket" --recursive >/dev/null 2>&1 && say "    bucket $bucket emptied"
  # Ask CloudFormation to delete everything that the stack created.
  a cloudformation delete-stack --stack-name "$STACK" || die "The stack could not be deleted."
  # Prepare the user for the waiting time.
  say "    deleting (the database takes a few minutes) ..."
  # Wait for the deletion; if no confirmation arrives, go on and look for leftovers.
  a cloudformation wait stack-delete-complete --stack-name "$STACK" 2>/dev/null || warn "CloudFormation did not confirm the deletion; checking what is left."
  # Make sure that nothing of Part A outlives its stack: a forgotten database would go on costing money.
  clear_leftovers
  # Success means: no stack, and no database with the name of the kit.
  if [ -z "$(stack_status)" ] && ! a rds describe-db-instances --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
    # Confirm.
    ok "managed services deleted; they no longer cost anything"
  else
    # Something is left: say where to look and what to delete by hand.
    warn "Something of Part A still exists. Open CloudFormation and RDS in the console, look for the names it505-services and $DB_ID, and delete them there."
  fi
  # The password of a deleted database is no longer needed.
  rm -f "$STATE_DIR/services.env"
}

cmd_check() {
  # Check the account.
  preflight
  # Print the title.
  say "${B}IT 505 · AWS Academy check${N}"
  say "  Account : $ACCOUNT        Region: $REGION"
  say "  Identity: $(a sts get-caller-identity --query Arn --output text)"
  # Look for the machine.
  find_instance
  # Show the machine and its state, or none.
  if [ -n "$INSTANCE" ]; then say "  Machine : $INSTANCE ($ITYPE) is $STATE_NAME"; else say "  Machine : none"; fi
  # The state of the stack of Part A.
  local st; st="$(stack_status)"
  # Show it, or none.
  say "  Services: ${st:-none}"
  say "  Backups : $(ls "$BACKUP_DIR"/it505-backup-*.tar.gz 2>/dev/null | wc -l) file(s) in $BACKUP_DIR"
  say ""
  say "  Limits of the Learner Lab to keep in mind (read the Readme of your lab for the current values):"
  say "    session of 4 hours · a fixed budget per student · Regions us-east-1 and us-west-2 · instance sizes up to 'large'"
  say "    the budget shown on the lab page is updated only every 8 to 12 hours"
}

# Print the explanation at the top of this file (lines 2 to 33) without the comment signs.
usage() { sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---- choose the command ----
cmd="${1:-help}"; [ $# -gt 0 ] && shift
case "$cmd" in
  check)            cmd_check ;;   # show the account and what exists
  deploy)           cmd_deploy "$@" ;;   # create the cloud twin
  install)          cmd_install ;;   # run the installer again
  status)           cmd_status ;;   # print the access card
  start)            cmd_start ;;   # start the twin
  stop)             cmd_stop ;;   # stop the twin
  myip)             cmd_myip "$@" ;;   # admit a new address
  ssh)              cmd_ssh ;;   # open a terminal on the twin
  backup)           cmd_backup ;;   # save and fetch a backup
  restore)          cmd_restore "$@" ;;   # load a backup into the twin
  destroy)          cmd_destroy ;;   # delete the twin
  rebuild)          cmd_rebuild "$@" ;;   # delete the twin and build it again
  services-up)      cmd_services_up ;;   # create the managed services
  services-status)  cmd_services_status ;;   # show the managed services
  services-down)    cmd_services_down ;;   # delete the managed services
  help|-h|--help)   usage ;;   # show the help
  *)                say "Unknown command: $cmd"; usage; exit 2 ;;   # unknown word: say so, show the help, report an error
esac
