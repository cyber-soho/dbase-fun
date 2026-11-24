#!/usr/bin/env bash
# =====================================================================================
#  it505_setup.sh — installs the database toolbox of the IT 505 lab machine
#  IT 505 · Fundamentals of Database Technologies · Cyber.SoHo Educational Hub
#  Version 1.0 (21 November 2026)
#
#  The same script builds two machines:
#    * the virtual machine on your own computer (VirtualBox, Debian 13 with LXQt)  -> profile "vm"
#    * its twin in AWS Academy (an EC2 instance started by it505_aws.sh)            -> profile "cloud"
#  It also runs on Ubuntu 24.04 / 26.04 and on Lubuntu.
#
#  Usage (inside the virtual machine, in a terminal):
#      sudo bash it505_setup.sh                 everything the three labs and the class demos need
#      sudo bash it505_setup.sh --core-only     only Labs 1 and 2: PostgreSQL, DBeaver, DuckDB, SQLite, JupyterLab
#      sudo bash it505_setup.sh --with-demo     adds podman for the demonstration engines (CouchDB, FerretDB, Neo4j, ...)
#      sudo bash it505_setup.sh --with-extras   adds MariaDB and R
#      sudo bash it505_setup.sh --all           all of the above
#  Other options: --profile vm|cloud   --user NAME   --pg-password TEXT   --pg-version 18
#                 --jupyter-password TEXT (cloud)   --desktop (cloud: remote desktop)   --yes (ask nothing)
#                 --env-file FILE (passwords in a file instead of on the command line; used by it505_aws.sh)
#
#  What it installs, by database family of the course:
#      flat and file-based : SQLite, DuckDB (command line and Python)
#      relational          : PostgreSQL 18 with the role "it505" and the database "mercadillo"; DBeaver Community
#      non-relational      : JSONB inside PostgreSQL; Valkey (key-value); CouchDB, FerretDB, Neo4j, Cassandra as demos
#      big data            : Parquet through DuckDB and PyArrow; Apache Spark (PySpark) with Java 21
#      blockchain          : Python's hashlib for hash chains; an Ethereum development node (Geth) as a demo
#      bridge to analysis  : JupyterLab, pandas, SQLAlchemy, psycopg, matplotlib
#  The script can be run again at any time: a step that is already done is not repeated.
#  A step that fails does not stop the others; the table at the end names every result.
#
#  Every tool is open-source software, and each can be replaced by another suitable tool
#  if you can justify the choice. Research your tools thoroughly before you rely on them.
#  Legal notice: https://cyber-soho.github.io/prevmon/00.01.%20cyber.soho%20-%20legal.html
# =====================================================================================

# Stop on the use of an unset variable; failures of single steps are handled by run_step below.
set -u
# New files are readable by everybody unless a step decides otherwise.
umask 022

# The version of this installer, printed in its title.
IT505_SETUP_VERSION="1.0 (21 November 2026)"

# ---- defaults; every one can be changed by an option or an environment variable ----
PROFILE="${IT505_PROFILE:-auto}"          # vm | cloud | auto (decide by looking at the hardware)
COMPONENTS="labs"                         # core = Labs 1-2 only; labs = all three labs and the class demos
WITH_DEMO=0                               # 1 = install podman for the demonstration engines
WITH_EXTRAS=0                             # 1 = install MariaDB and R
DESKTOP=0                                 # 1 = (cloud) install a remote desktop with DBeaver
ASSUME_YES=0                              # 1 = never ask a question
PG_VERSION="${IT505_PG_VERSION:-18}"      # the PostgreSQL major version of the course
PG_PASSWORD="${IT505_PG_PASSWORD:-}"      # password of the database role it505
JUPYTER_PASSWORD="${IT505_JUPYTER_PASSWORD:-}"   # password of JupyterLab on the cloud machine
TARGET_USER="${IT505_USER:-}"             # the account that will use the machine
ENV_FILE=""                               # optional file with IT505_PG_PASSWORD=... and IT505_JUPYTER_PASSWORD=... lines; deleted after reading
# DuckDB command-line client: version, address and SHA-256 fingerprints as published on duckdb.org on 21 November 2026.
DUCKDB_VERSION="2.0.1"
# The published SHA-256 fingerprints of the DuckDB archives; a download is used only if its fingerprint equals the one for its processor family (first amd64).
DUCKDB_SHA_AMD64="b676268be4d39e4e41a904442c9796c9914e645cc085c7505f048f2c992b5eca"
DUCKDB_SHA_ARM64="84e37891fcc45c887e30220f51a4914995cd8174139e87f8efd311ac83c956a7"   # the fingerprint of the arm64 archive
# Fingerprint of the key that signs the PostgreSQL package repository, as printed on postgresql.org.
PGDG_KEY_FPR="B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8"
# Where things go.
VENV=/opt/it505/venv
# The folder in which the installer keeps its notes: what was installed, and when.
STATE=/var/lib/it505
# The file that receives the complete output of every run.
LOG=/var/log/it505-setup.log

# ---- read the options ----
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)          PROFILE="${2:-}"; shift ;;   # vm or cloud; without it the installer finds out by itself
    --user)             TARGET_USER="${2:-}"; shift ;;   # the account that will use the machine
    --pg-password)      PG_PASSWORD="${2:-}"; shift ;;   # password of the database role it505
    --pg-version)       PG_VERSION="${2:-}"; shift ;;   # another major version of PostgreSQL
    --jupyter-password) JUPYTER_PASSWORD="${2:-}"; shift ;;   # password of JupyterLab on the cloud machine
    --env-file)         ENV_FILE="${2:-}"; shift ;;   # a file that holds the two passwords; it is deleted after reading
    --core-only)        COMPONENTS="core" ;;   # only what Labs 1 and 2 need
    --with-demo)        WITH_DEMO=1 ;;   # add podman for the demonstration engines
    --with-extras)      WITH_EXTRAS=1 ;;   # add MariaDB and R
    --all)              WITH_DEMO=1; WITH_EXTRAS=1 ;;   # both additions at once
    --desktop)          DESKTOP=1 ;;   # add a remote desktop on the cloud machine
    --yes|-y)           ASSUME_YES=1 ;;   # ask no question
    -h|--help)          sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;   # print the explanation at the top of this file, then stop
    *) echo "Unknown option: $1 (try --help)"; exit 2 ;;   # anything else is a typing mistake: say so and stop
  esac
  # Go on to the next word of the command line.
  shift
done

# ---- colours, only when the output is a terminal ----
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'; else G=""; R=""; Y=""; B=""; N=""; fi
# Print one line of text.
say()  { printf '%s\n' "$*"; }
# True when the named program is installed.
have() { command -v "$1" >/dev/null 2>&1; }
# True when this machine is managed by systemd (the normal case on Debian and Ubuntu).
have_systemd() { [ -d /run/systemd/system ]; }
# Run a command whose long output goes to the log file only; when it fails, show the last lines of that output.
quiet() { "$@" >>"$LOG" 2>&1 || { local rc=$?; tail -n 6 "$LOG" | sed 's/^/      /'; return "$rc"; }; }
# Install packages without asking questions. --no-install-recommends keeps the machine small.
# -o DPkg::Lock::Timeout=600: if another program is installing packages at this moment (automatic updates do), wait for it up to ten minutes.
apt_install() { say "  installing: $*"; DEBIAN_FRONTEND=noninteractive quiet apt-get -o DPkg::Lock::Timeout=600 install -y -q --no-install-recommends "$@"; }
# Start a service now and at every start of the machine; quietly do nothing where systemd is absent.
svc_enable_now() { if have_systemd; then systemctl enable --now "$1" >/dev/null 2>&1; else return 1; fi; }
# Run a command as the account that will use the machine (files it creates then belong to that account).
as_user() { runuser -u "$TARGET_USER" -- "$@"; }
# Does the key in file $1 have the fingerprint $2? GnuPG works in a throw-away folder and starts no background helper.
key_has_fingerprint() {
  # Without the program gpg the fingerprint cannot be read: go on without this check.
  have gpg || return 0
  # A throw-away folder, so that gpg leaves no files and no background helper behind.
  local tmp rc; tmp="$(mktemp -d)"
  # Show the key that the file holds and look for the expected fingerprint.
  GNUPGHOME="$tmp" gpg --batch --no-autostart --show-keys --with-colons "$1" 2>/dev/null | grep -q "$2"; rc=$?
  # Delete the folder and report whether the fingerprint was found.
  rm -rf "$tmp"; return "$rc"
}
# Produce a random password of 16 letters and digits.
random_password() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16; }
# A password that is safe in every place it is written: 8 to 64 letters, digits and . _ - + = @ %
valid_password() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._@%+=-]{8,64}$'; }

# =====================================================================================
#  Checks before anything is changed
# =====================================================================================
# The script installs software, so it must run as the administrator account root (through sudo).
if [ "$(id -u)" -ne 0 ]; then echo "Please run this script with sudo:  sudo bash $0"; exit 1; fi
# The script uses the package manager apt of Debian and Ubuntu.
have apt-get || { echo "This script needs a Debian or Ubuntu system (the program apt-get is missing)."; exit 1; }
# Read the name and release of the operating system; the sub-shells keep its variables apart from ours.
OS_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
# The code name of the release, for example trixie; package repositories are organised by it.
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-unknown}")"
# The full name of the system, for messages.
OS_NAME="$(. /etc/os-release; echo "${PRETTY_NAME:-unknown}")"
# Systems other than Debian and Ubuntu are not tested: warn, but continue.
case "$OS_ID" in debian|ubuntu) ;; *) say "${Y}Note: tested for Debian 13 and Ubuntu; this system is $OS_NAME. Continuing.${N}" ;; esac
# The processor family decides which downloads are used: amd64 (Intel, AMD) or arm64 (Apple Silicon, AWS Graviton).
ARCH="$(dpkg --print-architecture)"
# Only the two processor families for which every tool exists are accepted.
case "$ARCH" in amd64|arm64) ;; *) echo "Unsupported processor family: $ARCH"; exit 1 ;; esac

# Decide the profile when it was left on "auto": Amazon EC2 names itself in the hardware description.
if [ "$PROFILE" = "auto" ]; then
  # Without --profile: a machine at Amazon is the cloud twin, anything else is the local virtual machine.
  if grep -qi 'amazon' /sys/class/dmi/id/sys_vendor 2>/dev/null || grep -qi '^ec2' /sys/hypervisor/uuid 2>/dev/null; then PROFILE="cloud"; else PROFILE="vm"; fi
fi
# Refuse any other profile name.
case "$PROFILE" in vm|cloud) ;; *) echo "The profile must be vm or cloud."; exit 2 ;; esac

# Find the account that will use the machine: the one that called sudo, otherwise the first regular account.
[ -n "$TARGET_USER" ] || TARGET_USER="${SUDO_USER:-}"
# Without --user, or when root was named: take the first regular account (number 1000).
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then TARGET_USER="$(getent passwd 1000 | cut -d: -f1)"; fi
# Stop if that account does not exist.
getent passwd "$TARGET_USER" >/dev/null 2>&1 || { echo "No regular account found. Name one with: --user NAME"; exit 1; }
# Its home folder.
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
# The course folder inside it.
COURSE_DIR="$HOME_DIR/it505"

# At least 6 GB (gigabytes) of free disk space are needed; the tools use about 4 GB.
FREE_GB="$(df --output=avail -BG / | tail -n 1 | tr -dc '0-9')"
# Less than 3 GB free: stop, the installation cannot fit.
if [ "${FREE_GB:-0}" -lt 3 ]; then echo "Only ${FREE_GB} GB of disk space are free; at least 6 GB are needed."; exit 1; fi
# Less than 6 GB free: warn and continue.
[ "${FREE_GB:-0}" -lt 6 ] && say "${Y}Note: only ${FREE_GB} GB of disk space are free; 6 GB are recommended.${N}"

# Create the notes folder and the folder of the course software.
mkdir -p "$STATE" /opt/it505
# Passwords may arrive in a file instead of on the command line; read it, then delete it.
if [ -n "$ENV_FILE" ] && [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"; rm -f "$ENV_FILE"
  # Take the passwords from the file if it names them.
  PG_PASSWORD="${IT505_PG_PASSWORD:-$PG_PASSWORD}"; JUPYTER_PASSWORD="${IT505_JUPYTER_PASSWORD:-$JUPYTER_PASSWORD}"
fi
# Keep the original screen output as file descriptors 3 and 4, for the lines that must not reach the log.
exec 3>&1 4>&2
# Everything printed from here on is also written to the log file (without colour codes), so that a problem can be reported exactly.
exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >>"$LOG")) 2>&1
# Give the screen back and leave the log writer a moment to finish its last lines.
finish() { exec 1>&3 2>&4; sleep 0.5; }

# ---- the password of the database role ----
# Reuse the password of an earlier run, so that a saved DBeaver connection keeps working.
if [ -z "$PG_PASSWORD" ] && [ -r "$HOME_DIR/.pgpass" ]; then
  # An earlier run stored the password in ~/.pgpass: use it again, so that a second run changes nothing.
  PG_PASSWORD="$(awk -F: '$4 == "it505" {print $5; exit}' "$HOME_DIR/.pgpass")"
fi
# Ask for it when a person sits at the keyboard of the virtual machine.
if [ -z "$PG_PASSWORD" ] && [ "$PROFILE" = "vm" ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  # Ask for the password on the keyboard.
  say "${B}Choose the password of your database user 'it505'.${N}"
  say "8 to 64 characters: letters, digits and . _ - + = @ %   (write it down: DBeaver will ask for it)"
  # Repeat until two identical, acceptable entries were typed.
  while :; do
    # -s hides what is typed; -r keeps a backslash as a backslash.
    read -rs -p "Password: " P1; echo; read -rs -p "Again:    " P2; echo
    # The two entries differ: ask again.
    if [ "$P1" != "$P2" ]; then say "${R}The two entries differ. Try again.${N}"
    # The password breaks the rules: ask again.
    elif ! valid_password "$P1"; then say "${R}Not accepted: use 8 to 64 of the characters listed above.${N}"
    # Accepted: keep it and leave the loop.
    else PG_PASSWORD="$P1"; break; fi
  done
fi
# Otherwise generate one; it is shown at the end and stored in ~/.pgpass.
PG_PASSWORD_GENERATED=0
# Still no password (no keyboard, as on the cloud machine): create a random one and remember to show it at the end.
if [ -z "$PG_PASSWORD" ]; then PG_PASSWORD="$(random_password)"; PG_PASSWORD_GENERATED=1; fi
# A password given by option or file must obey the same rules.
valid_password "$PG_PASSWORD" || { echo "The database password must be 8 to 64 characters: letters, digits and . _ - + = @ %"; exit 2; }
# The cloud machine also needs a password for JupyterLab.
if [ "$PROFILE" = "cloud" ] && [ -z "$JUPYTER_PASSWORD" ]; then JUPYTER_PASSWORD="$(random_password)"; fi

# Print the title of the installer.
say "${B}IT 505 toolbox installer${N} $IT505_SETUP_VERSION"
say "System : $OS_NAME ($ARCH)      Profile: $PROFILE      Account: $TARGET_USER"
say "Scope  : $COMPONENTS$([ "$WITH_DEMO" -eq 1 ] && echo ' + demo engines')$([ "$WITH_EXTRAS" -eq 1 ] && echo ' + extras')$([ "$DESKTOP" -eq 1 ] && echo ' + remote desktop')      Log: $LOG"
printf '%s\n' "$PROFILE" >"$STATE/profile"; printf '%s\n' "$COMPONENTS" >"$STATE/components"
# Remember that a desktop was asked for.
[ "$DESKTOP" -eq 1 ] && echo yes >"$STATE/desktop"

# =====================================================================================
#  The steps
# =====================================================================================

# ---- 1. basic tools ----
step_base() {
  # A new cloud machine is still being prepared by its own first-start program; let that finish first.
  if [ "$PROFILE" = "cloud" ] && have cloud-init; then say "  waiting for the first-start preparation of the machine to finish"; cloud-init status --wait >/dev/null 2>&1 || true; fi
  # Read the current package lists; a failure here usually means "no internet connection".
  quiet apt-get update -q || say "  ${Y}the package lists could not be refreshed completely${N}"
  # ca-certificates + curl: safe downloads. gnupg: check signatures. git, zip, unzip, jq: everyday tools.
  # sqlite3: the SQLite database and its command-line client. python3-venv: separate Python environments.
  apt_install ca-certificates curl gnupg git zip unzip jq openssl sqlite3 python3 python3-venv
}

# ---- 2. PostgreSQL ----
# Add the package repository of the PostgreSQL project (PGDG), which carries every supported version.
add_pgdg_repo() {
  # postgresql-common is the packaging layer shared by all PostgreSQL versions on Debian and Ubuntu.
  apt_install postgresql-common || return 1
  # The folder in which the signing key of the PostgreSQL repository is stored.
  install -d /usr/share/postgresql-common/pgdg
  # Download the key with which the PostgreSQL project signs its packages.
  curl -fsSL --max-time 30 -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc || return 1
  # Compare the fingerprint of the downloaded key with the one printed on postgresql.org; refuse any other key.
  key_has_fingerprint /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc "$PGDG_KEY_FPR" || { say "  ${R}the repository key does not have the expected fingerprint${N}"; return 1; }
  # Describe the repository to apt: address, release name, and the key that must have signed it.
  cat >/etc/apt/sources.list.d/pgdg.sources <<EOF
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: ${CODENAME}-pgdg
Components: main
Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
EOF
  # Read the package list of this one repository; if that fails, remove the description again.
  quiet apt-get update -q -o Dir::Etc::sourcelist="sources.list.d/pgdg.sources" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" || { rm -f /etc/apt/sources.list.d/pgdg.sources; return 1; }
}

step_postgres() {
  # Install only when no PostgreSQL cluster exists yet.
  if ! have pg_lsclusters || [ -z "$(pg_lsclusters -h 2>/dev/null)" ]; then
    # First choice: the repository of the PostgreSQL project with the wanted version.
    if add_pgdg_repo && apt_install "postgresql-$PG_VERSION"; then
      # Say where the server came from.
      say "  PostgreSQL $PG_VERSION installed from the PostgreSQL project's repository"
    else
      # Fallback: the version that the distribution itself ships (17 on Debian 13, 16 on Ubuntu 24.04, 18 on Ubuntu 26.04).
      say "  ${Y}the PostgreSQL project's repository could not be used; installing the distribution's own PostgreSQL${N}"
      # Second choice: remove the unreachable repository again ...
      rm -f /etc/apt/sources.list.d/pgdg.sources
      # ... and install the PostgreSQL of the distribution itself.
      apt_install postgresql
    fi
  fi
  # Pick the cluster with the highest version: columns are version, name, port, status, owner, data folder, log file.
  local ver cluster port
  # Read version, name and port of the newest database cluster on this machine.
  read -r ver cluster port _ < <(pg_lsclusters -h | sort -k1,1nr | head -n 1) || true
  # No cluster: report the failure of this step.
  [ -n "${ver:-}" ] || { say "  ${R}no PostgreSQL cluster was created${N}"; return 1; }
  # Note version and port for the helper command and for later runs.
  printf '%s\n' "$ver" >"$STATE/pg_version"; printf '%s\n' "$port" >"$STATE/pg_port"
  # Start the server now and at every start of the machine.
  svc_enable_now postgresql || pg_ctlcluster "$ver" "$cluster" start </dev/null >/dev/null 2>&1 || true
  # Wait until the server accepts connections (at most 30 seconds).
  local tries=0; until pg_isready -q -p "$port" || [ "$tries" -ge 30 ]; do tries=$((tries + 1)); sleep 1; done
  # Stop this step if the server does not answer.
  pg_isready -q -p "$port" || { say "  ${R}the PostgreSQL server did not start${N}"; return 1; }
  # Create the course role and the course database if they are missing, and set the password.
  # \gexec runs the text produced by the SELECT as a command; :'pw' inserts the password as a quoted text.
  runuser -u postgres -- psql -p "$port" -X -q -v ON_ERROR_STOP=1 -v pw="$PG_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE it505 LOGIN CREATEDB' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'it505') \gexec
ALTER ROLE it505 PASSWORD :'pw';
SELECT 'CREATE DATABASE mercadillo OWNER it505' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mercadillo') \gexec
SQL
  # ~/.pgpass lets psql, pg_dump and the notebook connect without typing the password; only the owner may read it.
  ( umask 077; printf 'localhost:%s:*:it505:%s\n127.0.0.1:%s:*:it505:%s\n' "$port" "$PG_PASSWORD" "$port" "$PG_PASSWORD" >"$HOME_DIR/.pgpass" )
  # The password file belongs to the user and is readable by nobody else; psql refuses it otherwise.
  chown "$TARGET_USER": "$HOME_DIR/.pgpass"; chmod 600 "$HOME_DIR/.pgpass"
  # Show the result: version, port, role and database.
  say "  PostgreSQL $(runuser -u postgres -- psql -p "$port" -XAtc 'SHOW server_version') is running on port $port: role it505, database mercadillo"
}

# ---- 3. Python environment with JupyterLab ----
step_python() {
  # A virtual environment keeps the course's Python packages apart from those of the operating system.
  [ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
  # Bring pip, the Python package installer, up to date inside the environment.
  "$VENV/bin/python" -m pip install -q --no-cache-dir --upgrade pip
  # jupyterlab: the notebook. pandas: data frames. sqlalchemy + psycopg: the connection to PostgreSQL.
  # duckdb: the DuckDB engine inside Python. pyarrow: Parquet files. matplotlib: charts.
  say "  installing Python packages: jupyterlab pandas sqlalchemy psycopg duckdb pyarrow matplotlib (several minutes)"
  # Install the libraries of the course into that environment.
  "$VENV/bin/python" -m pip install -q --no-cache-dir jupyterlab pandas sqlalchemy "psycopg[binary]" duckdb pyarrow matplotlib
  # Give the environment to the user, so that further packages can be added without sudo.
  chown -R "$TARGET_USER": /opt/it505
  # Show the versions that were installed.
  say "  JupyterLab $("$VENV/bin/jupyter" lab --version 2>/dev/null), pandas $("$VENV/bin/python" -c 'import pandas; print(pandas.__version__)'), DuckDB for Python $("$VENV/bin/python" -c 'import duckdb; print(duckdb.__version__)')"
}

# ---- 4. DuckDB command-line client ----
step_duckdb() {
  # Already there from an earlier run: nothing to do.
  if have duckdb; then say "  already installed: $(duckdb --version)"; return 0; fi
  # Working variables.
  local sha url tmp bin
  # Choose the fingerprint that belongs to this processor family.
  [ "$ARCH" = "amd64" ] && sha="$DUCKDB_SHA_AMD64" || sha="$DUCKDB_SHA_ARM64"
  # The address of the official archive for this version and processor family.
  url="https://install.duckdb.org/v${DUCKDB_VERSION}/duckdb-cli-linux-${ARCH}.tar.gz"
  # A temporary folder for the download.
  tmp="$(mktemp -d)"
  # Download the official archive and compare its SHA-256 fingerprint with the published one before using it.
  if curl -fsSL --max-time 180 -o "$tmp/duckdb.tar.gz" "$url" && echo "$sha  $tmp/duckdb.tar.gz" | sha256sum -c --quiet - ; then
    # Unpack the archive.
    tar -xzf "$tmp/duckdb.tar.gz" -C "$tmp"
    # Find the program inside it.
    bin="$(find "$tmp" -type f -name duckdb | head -n 1)"
    # Install it for all users.
    [ -n "$bin" ] && install -m 0755 "$bin" /usr/local/bin/duckdb
  fi
  # Fallback: the same client as a Python package, published by the DuckDB project on the Python Package Index.
  if ! have duckdb; then
    # The archive could not be downloaded, or its fingerprint was wrong: say so.
    say "  ${Y}the archive from install.duckdb.org could not be used; installing the package duckdb-cli instead${N}"
    # Fall back to the same program from the Python package index.
    "$VENV/bin/python" -m pip install -q --no-cache-dir duckdb-cli && ln -sf "$VENV/bin/duckdb" /usr/local/bin/duckdb
    # The environment must stay the property of the user.
    chown -R "$TARGET_USER": /opt/it505
  fi
  # Delete the temporary folder.
  rm -rf "$tmp"
  # Show the installed version.
  have duckdb && say "  DuckDB $(duckdb --version)"
}

# ---- 5. DBeaver Community (the graphical SQL client) ----
step_dbeaver() {
  # Already there from an earlier run: nothing to do.
  if dpkg -s dbeaver-ce >/dev/null 2>&1; then say "  already installed: $(dpkg-query -W -f='${Version}' dbeaver-ce)"; return 0; fi
  # First choice: DBeaver's own package repository, so that later updates arrive with the system updates.
  if curl -fsSL --max-time 30 -o /usr/share/keyrings/dbeaver.asc https://dbeaver.io/debs/dbeaver.gpg.key && grep -q 'BEGIN PGP PUBLIC KEY BLOCK' /usr/share/keyrings/dbeaver.asc; then
    # The file ending .asc tells apt that the key is stored as text.
    echo "deb [signed-by=/usr/share/keyrings/dbeaver.asc] https://dbeaver.io/debs/dbeaver-ce /" >/etc/apt/sources.list.d/dbeaver.list
    # Read only this one repository, then install DBeaver from it.
    if quiet apt-get update -q -o Dir::Etc::sourcelist="sources.list.d/dbeaver.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" && apt_install dbeaver-ce; then
      # Say where DBeaver came from and finish the step.
      say "  DBeaver Community $(dpkg-query -W -f='${Version}' dbeaver-ce) installed from dbeaver.io"; return 0
    fi
    # The repository did not work: remove it again and try the package file.
    rm -f /etc/apt/sources.list.d/dbeaver.list
  fi
  # Second choice: the single package file from the download page.
  local file; [ "$ARCH" = "amd64" ] && file="dbeaver-ce-latest-linux-x86_64.deb" || file="dbeaver-ce-latest-linux-aarch64.deb"
  # Announce the download, because it takes a while.
  say "  downloading $file (about 130 MB)"
  # Download the package file from dbeaver.io and install it.
  curl -fsSL --max-time 900 -o "/tmp/$file" "https://dbeaver.io/files/$file" && DEBIAN_FRONTEND=noninteractive quiet apt-get -o DPkg::Lock::Timeout=600 install -y -q "/tmp/$file" && rm -f "/tmp/$file"
  # Show the installed version.
  dpkg -s dbeaver-ce >/dev/null 2>&1 && say "  DBeaver Community $(dpkg-query -W -f='${Version}' dbeaver-ce) installed from the package file"
}

# ---- 6. Valkey (key-value store) ----
step_valkey() {
  # valkey-server is the store itself; valkey-tools contains the client valkey-cli.
  have valkey-server || apt_install valkey-server valkey-tools
  # Start Valkey now and at every boot.
  svc_enable_now valkey-server || true
  # Check that the store listens only on this machine: "bind 127.0.0.1" and "protected-mode yes" are the packaged defaults.
  if grep -Eqs '^bind .*(0\.0\.0\.0|\*)' /etc/valkey/valkey.conf; then say "  ${Y}warning: Valkey listens on every network address; set 'bind 127.0.0.1 -::1' in /etc/valkey/valkey.conf${N}"; fi
  # The Python client, for the notebooks of Class 11.
  "$VENV/bin/python" -m pip install -q --no-cache-dir valkey || true
  # Show the version and the name of the client.
  say "  Valkey $(valkey-server --version 2>/dev/null | sed -n 's/.*v=\([0-9.]*\).*/\1/p') — client: valkey-cli"
}

# ---- 7. Apache Spark (PySpark) and the Java it needs ----
step_spark() {
  # Spark 4 runs on Java 17, 21 or 25; the headless edition has no graphical parts and is smaller.
  have java || apt_install openjdk-21-jre-headless || apt_install default-jre-headless
  # PySpark contains Spark itself; nothing else has to be downloaded.
  "$VENV/bin/python" -c "import pyspark" 2>/dev/null || { say "  installing the Python package pyspark (about 450 MB, several minutes)"; "$VENV/bin/python" -m pip install -q --no-cache-dir pyspark; }
  # The environment must stay the property of the user.
  chown -R "$TARGET_USER": /opt/it505
  # Show the versions of Spark and Java.
  say "  Apache Spark $("$VENV/bin/python" -c 'import pyspark; print(pyspark.__version__)') with Java $(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n 1)"
}

# ---- 8. the course folder ----
step_course_folder() {
  # data = your data files; starter = small test files; backups = files written by "it505 backup".
  as_user mkdir -p "$COURSE_DIR/data" "$COURSE_DIR/starter" "$COURSE_DIR/backups"
  # A five-row file used only by "it505 selftest". It is not the starter dataset of the labs.
  cat >"$COURSE_DIR/starter/it505_smoke_test.csv" <<'EOF'
id,item,quantity,unit_price
1,notebook,2,3.50
2,pencil,10,0.40
3,eraser,1,0.90
4,ruler,3,1.20
5,folder,4,2.10
EOF
  # A three-cell notebook that only proves the connection from Python to PostgreSQL.
  cat >"$COURSE_DIR/starter/00_environment_check.ipynb" <<'EOF'
{
 "cells": [
  {"cell_type": "markdown", "metadata": {}, "source": ["# IT 505 — environment check\n", "Run the two cells below with **Shift+Enter**. The first one connects to PostgreSQL, the second one reads a CSV file with DuckDB. This notebook is not part of any lab; it only proves that the bridge from Python to the databases works."]},
  {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["# getpass asks for the password without showing it; passwords never belong inside a notebook\n", "import getpass\n", "# pandas holds the result of a query as a data frame\n", "import pandas as pd\n", "# SQLAlchemy opens the connection; URL.create builds the address safely from its parts\n", "from sqlalchemy import create_engine, text\n", "from sqlalchemy.engine import URL\n", "# the address: driver psycopg, role it505, this machine, port 5432, database mercadillo\n", "url = URL.create('postgresql+psycopg', username='it505', password=getpass.getpass('Password of it505: '), host='localhost', port=5432, database='mercadillo')\n", "# ask the server for its version and show the answer as a one-row data frame\n", "pd.read_sql(text('SELECT version()'), create_engine(url))"]},
  {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["# DuckDB runs inside Python: no server and no password\n", "import duckdb\n", "# read the five-row test file directly from disk and return a data frame\n", "duckdb.sql(\"SELECT * FROM 'starter/it505_smoke_test.csv'\").df()"]}
 ],
 "metadata": {"kernelspec": {"display_name": "Python 3 (ipykernel)", "language": "python", "name": "python3"}, "language_info": {"name": "python"}},
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF
  # Write a short README into the course folder (the text up to the line EOF).
  cat >"$COURSE_DIR/README.txt" <<EOF
IT 505 · Fundamentals of Database Technologies — course folder
Built by it505_setup.sh $IT505_SETUP_VERSION on $(date '+%d %B %Y').

data/      put the starter file of the labs and your own data files here
starter/   it505_smoke_test.csv and 00_environment_check.ipynb (used by the self-test only)
backups/   written by:  it505 backup

Commands:  it505 status | it505 selftest | it505 notebook | it505 backup | it505 help
Database:  PostgreSQL on localhost:5432, database mercadillo, user it505 (password: the one you chose)
Legal notice: https://cyber-soho.github.io/prevmon/00.01.%20cyber.soho%20-%20legal.html
EOF
  # Everything in the course folder belongs to the user.
  chown -R "$TARGET_USER": "$COURSE_DIR"
  # Lab settings for every new terminal: psql connects to the course database, and the course Python comes first.
  if ! grep -qs 'IT 505 lab settings' "$HOME_DIR/.bashrc"; then
    # Add the lab settings to the start file of the terminal (the text up to the line EOF).
    cat >>"$HOME_DIR/.bashrc" <<'EOF'

# >>> IT 505 lab settings (added by it505_setup.sh) >>>
# psql without options connects to the course database as the course role.
export PGHOST=localhost PGUSER=it505 PGDATABASE=mercadillo
# python, pip, jupyter and duckdb of the course environment are found first.
export PATH="/opt/it505/venv/bin:$PATH"
# <<< IT 505 lab settings <<<
EOF
    # The start file belongs to the user.
    chown "$TARGET_USER": "$HOME_DIR/.bashrc"
  fi
  # Show where the course folder is.
  say "  course folder: $COURSE_DIR"
}

# ---- 9. the helper command it505 ----
step_helper() {
  # The text between the two marker lines is the complete helper program; it is written to /usr/local/bin/it505.
  cat >/usr/local/bin/it505 <<'IT505_HELPER_EOF'
#!/usr/bin/env bash
# =====================================================================================
#  it505 — the helper command of the IT 505 lab machine
#  IT 505 · Fundamentals of Database Technologies · Cyber.SoHo Educational Hub
#  Version 1.0 (21 November 2026). Installed by it505_setup.sh as /usr/local/bin/it505.
#
#  One command with a few sub-commands, so that a beginner never has to remember
#  where a service lives or how it is started:
#      it505 status      what is installed and what is running
#      it505 selftest    prove that every database family of the course works
#      it505 notebook    open JupyterLab in the course folder
#      it505 start|stop  postgresql | valkey
#      it505 demo ...    demonstration engines in containers (CouchDB, FerretDB, Neo4j, ...)
#      it505 backup      save your databases and your course folder in one file
#      it505 restore F   bring a backup file back
#      it505 audit       repeat the hardening checks of Guide 2
#  Legal notice: https://cyber-soho.github.io/prevmon/00.01.%20cyber.soho%20-%20legal.html
# =====================================================================================

# Treat the use of a variable that was never set as an error, so that typing mistakes are caught early.
set -u

# The version text printed by "it505 help".
VERSION="1.0 (21 November 2026)"
# The course folder of the current user; every lab file lives below it.
IT505_HOME="${IT505_HOME:-$HOME/it505}"
# The Python environment that it505_setup.sh created for the course (JupyterLab, pandas, DuckDB, PySpark).
VENV="${IT505_VENV:-/opt/it505/venv}"
# The folder where the installer left small notes about what it installed.
STATE="${IT505_STATE:-/var/lib/it505}"
# The tiny CSV (Comma-Separated Values) file that the self-test reads.
SMOKE_CSV="$IT505_HOME/starter/it505_smoke_test.csv"
# Name of the database role and of the course database created by the installer.
PGUSER_IT505="it505"
# The database of the course.
PGDB_IT505="mercadillo"

# ---- colours: only when the output is a terminal, so that saved logs stay clean ----
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'; else G=""; R=""; Y=""; B=""; N=""; fi

# Print one line of a result table: a coloured word, then the text.
pass() { printf '  %s[PASS]%s %s\n' "$G" "$N" "$*"; PASSED=$((PASSED + 1)); }
# Print a red FAIL line and count it.
fail() { printf '  %s[FAIL]%s %s\n' "$R" "$N" "$*"; FAILED=$((FAILED + 1)); }
# Print a yellow SKIP line and count it.
skip() { printf '  %s[SKIP]%s %s\n' "$Y" "$N" "$*"; SKIPPED=$((SKIPPED + 1)); }
# Print one line of text.
info() { printf '%s\n' "$*"; }
# Counters used by the self-test.
PASSED=0; FAILED=0; SKIPPED=0

# True when a program with this name can be found.
have() { command -v "$1" >/dev/null 2>&1; }
# True when this machine is managed by systemd (the normal case on Debian and Ubuntu).
have_systemd() { [ -d /run/systemd/system ]; }
# Read one note left by the installer (for example the installation profile); empty when absent.
note() { [ -r "$STATE/$1" ] && cat "$STATE/$1" || true; }
# Run psql as the course role on this machine; ~/.pgpass supplies the password.
pg() { psql -h localhost -U "$PGUSER_IT505" -d "${PGDB:-$PGDB_IT505}" -X -A -t "$@"; }
# The same call as a list of words, for places that need a real program instead of a shell function.
PSQL=(psql -h localhost -U "$PGUSER_IT505" -d "$PGDB_IT505" -X -A -t)

# -------------------------------------------------------------------------------------
#  run_check FAMILY "what is tested" "expected pattern" command...
#  Runs the command with a time limit, compares the last output line with the pattern,
#  and prints PASS or FAIL. The command is never shown to the student unless it fails.
# -------------------------------------------------------------------------------------
run_check() {
  # Take the three fixed arguments; what remains is the command to run.
  local family="$1" what="$2" expect="$3"; shift 3
  # Variables for the output and the exit code of that command.
  local out rc
  # "timeout 120" stops a test that hangs; 2>&1 keeps error messages together with the output.
  out="$(timeout 120 "$@" 2>&1)"; rc=$?
  # Keep only the last non-empty line: that is where every test prints its answer.
  local last; last="$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | tail -n 1)"
  # Success means: the command ended without error and its last line looks as expected.
  if [ "$rc" -eq 0 ] && printf '%s' "$last" | grep -Eq -- "$expect"; then
    # Report the family, the test and the answer that was received.
    pass "$(printf '%-14s %s  ->  %s' "$family" "$what" "$last")"
  else
    # Report the failure; the reason is printed below it.
    fail "$(printf '%-14s %s' "$family" "$what")"
    # Show at most three lines of the reason, indented, so that the student can report them.
    printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | tail -n 3 | sed 's/^/           /'
  fi
}

# -------------------------------------------------------------------------------------
#  it505 selftest — one test for each database family of the course
# -------------------------------------------------------------------------------------
cmd_selftest() {
  # Print the title of the self-test.
  info "${B}IT 505 self-test${N} — one check for every database family of the course"
  info "Machine: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}"), profile: $(note profile), $(date '+%d %B %Y %H:%M')"
  info ""

  # 1. Flat file: the small test file exists and holds five data rows below its header line.
  if [ -r "$SMOKE_CSV" ]; then
    # Count the data rows of the test file: five are expected.
    run_check "Flat file" "the test CSV has 5 data rows" '^5$' bash -c "tail -n +2 '$SMOKE_CSV' | grep -c ."
  else
    # The test file is missing: report it.
    fail "Flat file      the test file $SMOKE_CSV is missing (run the installer again)"
  fi

  # 2. File-based database: SQLite answers with its version.
  if have sqlite3; then
    # Ask SQLite for its version, using a database that exists only in memory.
    run_check "File-based" "SQLite answers" '^SQLite 3\.' sqlite3 :memory: "SELECT 'SQLite ' || sqlite_version();"
  # SQLite is missing: report it.
  else fail "File-based     sqlite3 is not installed"; fi

  # 3. File-based database: DuckDB reads the CSV file directly, without importing it first.
  if have duckdb; then
    # Let DuckDB count the rows of the CSV file directly from the disk.
    run_check "File-based" "DuckDB reads the CSV file where it lies" '^5$' duckdb -noheader -csv -c "SELECT count(*) FROM read_csv('$SMOKE_CSV');"
  # DuckDB is missing: report it.
  else fail "File-based     duckdb is not installed"; fi

  # 4. Relational: the PostgreSQL server accepts a connection over the network address of this machine.
  if have psql; then
    # Ask the PostgreSQL server for its version over the network address localhost.
    run_check "Relational" "PostgreSQL answers on localhost:5432" '^PostgreSQL [0-9]+' "${PSQL[@]}" -c "SELECT 'PostgreSQL ' || current_setting('server_version');"
    # 5. Advanced SQL of Classes 9 and 11: a recursive query adds the numbers 1 to 5.
    run_check "Relational" "a recursive query (WITH RECURSIVE) works" '^15$' "${PSQL[@]}" -c "WITH RECURSIVE t(n) AS (VALUES (1) UNION ALL SELECT n + 1 FROM t WHERE n < 5) SELECT sum(n) FROM t;"
    # 6. Document family inside PostgreSQL: the JSONB type and its ->> operator.
    run_check "Document" "PostgreSQL reads a field of a JSONB value" '^Madrid$' "${PSQL[@]}" -c "SELECT '{\"city\": \"Madrid\"}'::jsonb ->> 'city';"
  # The client psql is missing: report it.
  else fail "Relational     psql is not installed"; fi

  # 7. The bridge of Class 10: pandas reads a query result through SQLAlchemy and psycopg.
  if [ -x "$VENV/bin/python" ]; then
    # Run a short Python program that reads one row from PostgreSQL into a pandas data frame.
    run_check "Notebook" "pandas reads from PostgreSQL (SQLAlchemy)" '^1 row' "$VENV/bin/python" -c '
# Libraries: os for the path of the password file, pandas for the data frame.
import os, pandas as pd
# SQLAlchemy opens the connection and marks a text as an SQL statement.
from sqlalchemy import create_engine, text
# URL builds the connection address from its parts, so that special characters in the password do no harm.
from sqlalchemy.engine import URL
# Read the password from ~/.pgpass, the file in which PostgreSQL clients keep it (host:port:database:user:password).
pw = ""
# Read the password of the role it505 from the file ~/.pgpass.
for line in open(os.path.expanduser("~/.pgpass")):
    # Each line of that file holds host:port:database:user:password.
    parts = line.rstrip("\n").split(":")
    # Take the line that belongs to the user it505.
    if len(parts) >= 5 and parts[3] == "it505":
        # The password is everything after the fourth colon.
        pw = ":".join(parts[4:])
# Build the connection address for the driver psycopg.
url = URL.create("postgresql+psycopg", username="it505", password=pw, host="localhost", port=5432, database="mercadillo")
# Run a one-row query and receive the result as a data frame.
df = pd.read_sql(text("SELECT 1 AS ok"), create_engine(url))
# Print the number of rows; the self-test looks for this line.
print(len(df), "row read into a pandas data frame")
'
    # 8. JupyterLab itself.
    run_check "Notebook" "JupyterLab is installed" '^[0-9]+\.[0-9]+' "$VENV/bin/jupyter" lab --version
  # The Python environment of the course is missing: report it.
  else fail "Notebook       the course Python environment $VENV is missing"; fi

  # 9. Key-value: Valkey stores a value with an expiry time and returns it.
  if have valkey-cli; then
    # Store a value in Valkey that expires after ten seconds, then read it back.
    run_check "Key-value" "Valkey stores and returns a value" '^ok$' bash -c "valkey-cli SET it505:selftest ok EX 10 >/dev/null && valkey-cli GET it505:selftest"
  # A core-only installation has no Valkey: that is a skip, not a failure.
  elif [ "$(note components)" = "core" ]; then skip "Key-value      Valkey was not installed (core-only installation)"
  # Valkey is missing although it should be there: report it.
  else fail "Key-value      valkey-cli is not installed"; fi

  # 10. Big data, laptop size: DuckDB writes 100,000 rows to a Parquet file and counts them back.
  if have duckdb; then
    # A temporary file name for the Parquet test.
    local pq; pq="$(mktemp --suffix=.parquet)"
    # Write 100000 numbers into a Parquet file and count them again from the file.
    run_check "Big data" "DuckDB writes and reads a Parquet file" '^100000$' duckdb -noheader -csv -c "COPY (SELECT * FROM range(100000)) TO '$pq' (FORMAT parquet); SELECT count(*) FROM '$pq';"
    # Remove the temporary file.
    rm -f "$pq"
  fi

  # 11. Big data, cluster engine: Apache Spark starts on this one machine and counts 1,000 rows.
  if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import pyspark" 2>/dev/null; then
    # Tell the user that the next check takes a moment.
    info "  ...   starting Apache Spark; the first start takes about 20 seconds"
    # Run a short Python program that starts Spark and counts 1000 rows.
    run_check "Big data" "Apache Spark starts and counts rows" '^1000 rows' "$VENV/bin/python" -c '
# The entry point of Spark for Python.
from pyspark.sql import SparkSession
# local[1] = one worker thread on this machine; the web interface is switched off because nobody will look at it here.
spark = (SparkSession.builder.master("local[1]").appName("it505-selftest")
         # No web interface and little memory: this is only a test.
         .config("spark.ui.enabled", "false").config("spark.driver.memory", "512m")
         # One partition is enough for a thousand rows.
         .config("spark.sql.shuffle.partitions", "1").getOrCreate())
# Show errors only, not the progress messages of Spark.
spark.sparkContext.setLogLevel("ERROR")
# Create the numbers 0 to 999 and count them.
n = spark.range(1000).count()
# Print the count and the version; the self-test looks for this line.
print(n, "rows counted by Spark", spark.version)
# Stop Spark and free its memory.
spark.stop()
'
  # A core-only installation has no Spark: that is a skip, not a failure.
  elif [ "$(note components)" = "core" ]; then skip "Big data       Apache Spark was not installed (core-only installation)"
  # PySpark is missing although it should be there: report it.
  else fail "Big data       PySpark is not installed in $VENV"; fi

  # 12. Ledger: the SHA-256 fingerprint function that every blockchain is built on.
  if [ -x "$VENV/bin/python" ]; then
    # Compute the SHA-256 fingerprint of the text IT505 and compare its beginning with the known value.
    run_check "Ledger" "SHA-256 fingerprints are computed" '^bfa2635b434087af' "$VENV/bin/python" -c 'import hashlib; print(hashlib.sha256(b"IT505").hexdigest()[:16], "(first 16 characters)")'
  fi

  # 13. The graphical client, only where a desktop exists.
  if [ "$(note profile)" = "vm" ] || [ "$(note desktop)" = "yes" ]; then
    # On the desktop machine DBeaver must be installed: show its version.
    if dpkg -s dbeaver-ce >/dev/null 2>&1; then pass "$(printf '%-14s %s  ->  %s' "Client" "DBeaver Community is installed" "$(dpkg-query -W -f='${Version}' dbeaver-ce 2>/dev/null)")"
    # DBeaver is missing: report it.
    else fail "Client         DBeaver Community is not installed"; fi
  fi

  # An empty line before the result.
  info ""
  # No failure: say that the machine is ready. Otherwise point to the help.
  if [ "$FAILED" -eq 0 ]; then
    # The good result, in green.
    info "${G}${B}Result: $PASSED passed, $SKIPPED skipped, 0 failed.${N} The machine is ready for the labs."
  else
    # The result with failures, in red, with the place to look for help.
    info "${R}${B}Result: $PASSED passed, $SKIPPED skipped, $FAILED failed.${N} Read the lines marked FAIL, then see the Help section of Guide 3."
  fi
  # Give the number of failures back as the exit code, so that other scripts can test it.
  return "$FAILED"
}

# -------------------------------------------------------------------------------------
#  it505 status — what is installed and what is running
# -------------------------------------------------------------------------------------
# Print one aligned line: name, state, details. The state is padded first and coloured afterwards, so that columns stay aligned.
row() { printf '  %-22s %s%-13s%s %s\n' "$1" "${4:-}" "$2" "$N" "$3"; }
# Is a TCP (Transmission Control Protocol) port open on this machine? Uses bash only, no extra program.
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

cmd_status() {
  # Print the heading: the system and the profile of this machine.
  info "${B}IT 505 lab machine${N} — $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-}") — profile: $(note profile)"
  info ""
  # PostgreSQL: the version comes from the server itself when it answers, otherwise from the installer's note.
  if have psql; then
    # PostgreSQL answers on its port: show version, address and database.
    if port_open 5432; then row "PostgreSQL $(pg -c "SHOW server_version" 2>/dev/null | cut -d' ' -f1)" "running" "localhost:5432 · database $PGDB_IT505 · user $PGUSER_IT505" "$G"
    # It is installed but not running: say how to start it.
    else row "PostgreSQL $(note pg_version)" "stopped" "start it with: it505 start postgresql" "$R"; fi
  # It is not installed at all.
  else row "PostgreSQL" "missing" "run the installer again"; fi
  # Valkey.
  if have valkey-server; then
    # Valkey answers on its port: show version and address.
    if port_open 6379; then row "Valkey $(valkey-server --version 2>/dev/null | sed -n 's/.*v=\([0-9.]*\).*/\1/p')" "running" "localhost:6379 · client: valkey-cli" "$G"
    # It is installed but not running: say how to start it.
    else row "Valkey" "stopped" "start it with: it505 start valkey" "$R"; fi
  # It was left out by a core-only installation.
  else row "Valkey" "not installed" "(core-only installation)"; fi
  # JupyterLab.
  if [ -x "$VENV/bin/jupyter" ]; then
    # JupyterLab is running: show its port.
    if port_open 8888; then row "JupyterLab $("$VENV/bin/jupyter" lab --version 2>/dev/null)" "running" "port 8888" "$G"
    # It is installed and waits to be started.
    else row "JupyterLab $("$VENV/bin/jupyter" lab --version 2>/dev/null)" "ready" "start it with: it505 notebook"; fi
  fi
  # Programs that are not services: they run only while you use them.
  have duckdb  && row "DuckDB $(duckdb --version 2>/dev/null | awk '{print $1}' | sed 's/^v//')" "ready" "command: duckdb"
  # SQLite needs no server: show its version if it is installed.
  have sqlite3 && row "SQLite $(sqlite3 --version 2>/dev/null | awk '{print $1}')" "ready" "command: sqlite3"
  # The same for DBeaver, taken from the package list.
  dpkg -s dbeaver-ce >/dev/null 2>&1 && row "DBeaver $(dpkg-query -W -f='${Version}' dbeaver-ce 2>/dev/null)" "ready" "application menu, or command: dbeaver"
  # The same for Java, which Apache Spark needs.
  have java && row "Java $(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n 1)" "ready" "needed by Apache Spark"
  # The same for Apache Spark, asked from the Python library.
  [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import pyspark" 2>/dev/null && row "Apache Spark $("$VENV/bin/python" -c 'import pyspark; print(pyspark.__version__)')" "ready" "inside the notebook: from pyspark.sql import SparkSession"
  # Demonstration engines, when podman is installed.
  if have podman; then
    # An empty line before the list of demonstration engines.
    info ""
    info "  Demonstration engines (containers):"
    # Ask podman for the engines of the course and their state.
    local lines; lines="$(podman ps -a --filter name=it505- --format '    {{.Names}}  {{.Status}}' 2>/dev/null)"
    # Print them, or say that none exists yet.
    [ -n "$lines" ] && printf '%s\n' "$lines" || info "    none created yet — see: it505 demo list"
  fi
  # An empty line before the closing hints.
  info ""
  # Disk and memory, the two limits of a small virtual machine.
  info "  Disk:   $(df -h --output=used,size,pcent / | tail -n 1 | awk '{print $1" used of "$2" ("$3")"}')"
  info "  Memory: $(free -m | awk '/^Mem:/{print $3" MB used of "$2" MB"}')"
  # On the cloud machine, name the file that holds the addresses and passwords.
  [ "$(note profile)" = "cloud" ] && [ -r "$IT505_HOME/ACCESS.txt" ] && info "  Addresses and passwords of this cloud machine: $IT505_HOME/ACCESS.txt"
  # This overview itself never fails.
  return 0
}

# -------------------------------------------------------------------------------------
#  it505 start | stop | restart  postgresql | valkey
# -------------------------------------------------------------------------------------
cmd_service() {
  # The action (start, stop, restart) and the name of the service.
  local action="$1" name="${2:-}" unit=""
  case "$name" in
    postgresql|postgres|pg) unit="postgresql" ;;   # accept three spellings of PostgreSQL
    valkey) unit="valkey-server" ;;   # the service of Valkey is called valkey-server
    *) info "Usage: it505 $action postgresql | valkey"; return 2 ;;   # any other name: show the usage and stop
  esac
  # With systemd, hand the action to systemctl.
  if have_systemd; then
    # sudo asks for your password because starting and stopping a service changes the whole machine.
    sudo systemctl "$action" "$unit" && info "$unit: $action done." && return 0
  else
    # Without systemd this helper cannot manage services: say what to use instead.
    info "This machine has no systemd; use the service's own command (pg_ctlcluster, valkey-server)."
  fi
  # Report the failure to the caller.
  return 1
}

# -------------------------------------------------------------------------------------
#  it505 notebook — JupyterLab in the course folder
# -------------------------------------------------------------------------------------
cmd_notebook() {
  # Stop here if JupyterLab is not installed.
  [ -x "$VENV/bin/jupyter" ] || { info "JupyterLab is not installed in $VENV."; return 1; }
  # On the cloud machine JupyterLab already runs as a service.
  if [ "$(note profile)" = "cloud" ]; then
    # Say where its address and password are.
    info "On the cloud machine JupyterLab runs as a service. Its address and password are in $IT505_HOME/ACCESS.txt"
    # Nothing else to do.
    return 0
  fi
  # Make sure that the course folder exists.
  mkdir -p "$IT505_HOME"
  # Explain how to stop JupyterLab before it takes over the terminal.
  info "JupyterLab opens in your browser. To stop it, come back to this window and press Ctrl+C twice."
  # --ServerApp.root_dir limits the file browser of JupyterLab to the course folder.
  cd "$IT505_HOME" && exec "$VENV/bin/jupyter" lab --ServerApp.root_dir="$IT505_HOME"
}

# -------------------------------------------------------------------------------------
#  it505 demo — demonstration engines in containers (professor's machine)
#  Every engine listens only on 127.0.0.1, so nothing outside this machine can reach it.
# -------------------------------------------------------------------------------------
# The password shared by the demonstration engines; created once, readable only by you.
demo_password() {
  # The file that keeps the password of the demonstration engines.
  local f="$IT505_HOME/.demo_password"
  # Create it once, readable only by its owner, with 16 random letters and digits.
  if [ ! -s "$f" ]; then mkdir -p "$IT505_HOME"; (umask 077; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 >"$f"); fi
  # Print the password.
  cat "$f"
}

# Describe one engine: where its image comes from, which ports it opens, how it is configured.
demo_def() {
  # The password that every engine receives.
  local pw; pw="$(demo_password)"
  # Start with empty settings; the lines below fill them for the chosen engine.
  IMGS=(); PORTS=(); ENVS=(); ARGS=(); NOTE=""; LICENCE=""
  case "$1" in
    couchdb)
      # Where the image of CouchDB can be downloaded: two registries, tried in this order.
      IMGS=("public.ecr.aws/docker/library/couchdb:3" "docker.io/library/couchdb:3")
      # Port 5984, open only on this machine; the name and password of the administrator.
      PORTS=(-p 127.0.0.1:5984:5984); ENVS=(-e COUCHDB_USER=it505 -e "COUCHDB_PASSWORD=$pw")
      # Licence and a one-line description for the user.
      LICENCE="Apache 2.0"; NOTE="Document database. Web interface (Fauxton): http://localhost:5984/_utils   user: it505   password: $pw" ;;
    ferretdb)
      # The evaluation image of FerretDB, which contains its own PostgreSQL.
      IMGS=("ghcr.io/ferretdb/ferretdb-eval:2")
      # Port 27017, open only on this machine; user and password of the database.
      PORTS=(-p 127.0.0.1:27017:27017); ENVS=(-e POSTGRES_USER=it505 -e "POSTGRES_PASSWORD=$pw")
      # Licence and a one-line description for the user.
      LICENCE="Apache 2.0"; NOTE="Document database that speaks the MongoDB protocol on top of PostgreSQL. Shell: it505 demo shell ferretdb   user: it505   password: $pw" ;;
    neo4j)
      # Where the image of Neo4j Community can be downloaded.
      IMGS=("public.ecr.aws/docker/library/neo4j:community" "docker.io/library/neo4j:community")
      # Port 7474 for the browser, port 7687 for the database protocol; both only on this machine.
      PORTS=(-p 127.0.0.1:7474:7474 -p 127.0.0.1:7687:7687)
      # The password, and memory limits that fit a small lab machine.
      ENVS=(-e "NEO4J_AUTH=neo4j/$pw" -e NEO4J_server_memory_heap_initial__size=256m -e NEO4J_server_memory_heap_max__size=512m -e NEO4J_server_memory_pagecache_size=128m)
      # Licence and a one-line description for the user.
      LICENCE="GPL 3.0 (Community Edition)"; NOTE="Graph database. Browser: http://localhost:7474   user: neo4j   password: $pw" ;;
    cassandra)
      # Where the image of Cassandra can be downloaded.
      IMGS=("public.ecr.aws/docker/library/cassandra:5" "docker.io/library/cassandra:5")
      # Port 9042, open only on this machine; memory limits for a small machine.
      PORTS=(-p 127.0.0.1:9042:9042); ENVS=(-e MAX_HEAP_SIZE=512M -e HEAP_NEWSIZE=128M)
      # Licence and a one-line description for the user.
      LICENCE="Apache 2.0"; NOTE="Wide-column store. It needs about one minute to start. Shell: it505 demo shell cassandra" ;;
    geth)
      # The official image of the Ethereum client Geth.
      IMGS=("docker.io/ethereum/client-go:stable")
      # Port 8545 only on this machine; --dev starts a private test chain, --http lets programs talk to it.
      PORTS=(-p 127.0.0.1:8545:8545); ARGS=(--dev --http --http.addr 0.0.0.0 --http.api "eth,net,web3" --http.vhosts "*")
      # Licence and a one-line description for the user.
      LICENCE="LGPL 3.0 and GPL 3.0"; NOTE="Ethereum client in development mode: a private chain on this machine, no real money. JSON-RPC: http://localhost:8545   Shell: it505 demo shell geth" ;;
    *) return 1 ;;   # an unknown name: report failure to the caller
  esac
}
# The names of the five engines.
DEMO_ENGINES="couchdb ferretdb neo4j cassandra geth"

cmd_demo() {
  # The sub-command (list by default) and the name of the engine.
  local sub="${1:-list}" name="${2:-}"
  # Nothing works without podman: say how to install it.
  have podman || { info "podman is not installed. Run the installer again with the option --with-demo."; return 1; }
  case "$sub" in
    list)
      # Print the heading of the list.
      info "${B}Demonstration engines${N} (run on the professor's machine; students do not need them):"
      # One line per engine: name, licence, first sentence of its description.
      local e; for e in $DEMO_ENGINES; do demo_def "$e"; printf '  %-10s %-28s %s\n' "$e" "[$LICENCE]" "${NOTE%%.*}."; done
      # Finish with the two most useful commands.
      info ""; info "Start one with:  it505 demo start NAME      Stop everything with:  it505 demo stop all" ;;
    start)
      # Load the settings of the engine; stop if the name is unknown.
      demo_def "$name" || { info "Unknown engine '$name'. Known: $DEMO_ENGINES"; return 2; }
      # If the container exists already, start it again; its data are still there.
      if podman container exists "it505-$name" 2>/dev/null; then
        # The container exists already: start it again.
        podman start "it505-$name" >/dev/null && info "${G}it505-$name started again.${N}"
      else
        # Otherwise download an image: try each registry until one answers.
        local img="" i
        # Try each source of the image in turn; the first one that answers is used.
        for i in "${IMGS[@]}"; do info "Downloading $i (first start only) ..."; if podman pull -q "$i" >/dev/null; then img="$i"; break; fi; done
        # No registry answered: say so and stop.
        [ -n "$img" ] || { info "${R}No image could be downloaded. Check the internet connection and try again.${N}"; return 1; }
        # Create and start the container with the ports, settings and arguments of the engine.
        podman run -d --name "it505-$name" "${PORTS[@]}" "${ENVS[@]}" "$img" "${ARGS[@]}" >/dev/null || return 1
        # Confirm the start.
        info "${G}it505-$name created and started.${N}"
      fi
      # Show how to reach the engine.
      info "$NOTE" ;;
    stop)
      # The name all stops every engine of the course.
      if [ "$name" = "all" ]; then local e; for e in $DEMO_ENGINES; do podman stop "it505-$e" >/dev/null 2>&1 && info "it505-$e stopped."; done; return 0; fi
      # Stop one engine; its data stay on the disk.
      podman stop "it505-$name" >/dev/null && info "it505-$name stopped. Its data are kept; 'it505 demo start $name' brings it back." ;;
    rm)
      # Remove one engine together with its data.
      podman rm -f "it505-$name" >/dev/null && info "it505-$name removed together with its data." ;;
    shell)
      # Load the settings of the engine; stop if the name is unknown.
      demo_def "$name" || { info "Unknown engine '$name'."; return 2; }
      # The shells of the engines need the password.
      local pw; pw="$(demo_password)"
      case "$name" in
        ferretdb)  podman exec -it "it505-$name" mongosh "mongodb://it505:$pw@localhost:27017/" ;;   # the MongoDB shell inside the FerretDB container
        neo4j)     podman exec -it "it505-$name" cypher-shell -u neo4j -p "$pw" ;;   # the Cypher shell of Neo4j
        cassandra) podman exec -it "it505-$name" cqlsh ;;   # the CQL shell of Cassandra
        geth)      podman exec -it "it505-$name" geth attach http://127.0.0.1:8545 ;;   # the JavaScript console of Geth
        couchdb)   info "CouchDB is used through HTTP. Try:  curl -u it505:$pw http://localhost:5984/_all_dbs" ;;   # CouchDB has no shell: show a web request instead
      esac ;;
    status) podman ps -a --filter name=it505- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' ;;   # list the containers of the course with state and ports
    *) info "Usage: it505 demo list | start NAME | stop NAME|all | shell NAME | status | rm NAME"; return 2 ;;   # anything else: show the usage
  esac
}

# -------------------------------------------------------------------------------------
#  it505 backup — one file with your databases, your course folder and your DBeaver scripts
# -------------------------------------------------------------------------------------
cmd_backup() {
  # The target folder (the backups folder by default) and working variables.
  local dest="${1:-$IT505_HOME/backups}" ts tmp out db n=0
  # A time stamp for the file name, a temporary work folder, and the name of the result.
  ts="$(date +%Y%m%d-%H%M)"; tmp="$(mktemp -d)"; out="$dest/it505-backup-$ts.tar.gz"
  # Create the target folder and the work folder.
  mkdir -p "$dest" "$tmp/db"
  # Print the title.
  info "${B}IT 505 backup${N}"
  # 1. Every database that belongs to the course role, each in PostgreSQL's own compressed dump format.
  for db in $(PGDB=postgres pg -c "SELECT d.datname FROM pg_database d JOIN pg_roles r ON r.oid = d.datdba WHERE r.rolname = '$PGUSER_IT505' AND NOT d.datistemplate ORDER BY 1" 2>/dev/null); do
    # Save one database in the compact format of pg_dump, without the name of its owner.
    if pg_dump -h localhost -U "$PGUSER_IT505" -Fc --no-owner -f "$tmp/db/$db.dump" "$db" 2>"$tmp/err"; then info "  database $db saved"; n=$((n + 1)); else info "  ${R}database $db could not be saved:${N} $(head -n 1 "$tmp/err")"; fi
  done
  # Warn if no database could be saved.
  [ "$n" -gt 0 ] || info "  ${Y}no PostgreSQL database was saved (is the server running? it505 status)${N}"
  # 2. The course folder, without the backups themselves and without files above 100 MB (the ten-million-row files of Class 12 can be produced again).
  ( cd "$HOME" && [ -d it505 ] && find it505 -path it505/backups -prune -o -type f -size -100M -print0 | tar --null -cf "$tmp/files.tar" -T - ) 2>/dev/null && info "  course folder saved (files above 100 MB are left out)"
  # 3. The SQL scripts and connection list that DBeaver keeps in its own workspace.
  if [ -d "$HOME/.local/share/DBeaverData/workspace6/General" ]; then
    # Save the scripts and the connection list of DBeaver, if DBeaver was used.
    ( cd "$HOME" && tar -cf "$tmp/dbeaver.tar" .local/share/DBeaverData/workspace6/General ) 2>/dev/null && info "  DBeaver scripts and connection list saved"
  fi
  # 4. A short description, so that the file explains itself.
  {
    # Write a short description of the backup: date and machine first.
    echo "IT 505 backup made on $(date '+%d %B %Y %H:%M') on $(hostname)"
    echo "PostgreSQL server: $(pg -c 'SHOW server_version' 2>/dev/null)"
    echo "Databases: $(cd "$tmp/db" && ls 2>/dev/null | tr '\n' ' ')"
    echo "Restore with: it505 restore <this file>"
  # Everything printed inside the braces goes into the file MANIFEST.txt of the backup.
  } >"$tmp/MANIFEST.txt"
  # Remove the error log, pack everything into one compressed file, and delete the work folder.
  rm -f "$tmp/err"; tar -czf "$out" -C "$tmp" . && rm -rf "$tmp"
  # Show the name and the size of the backup file.
  info "${G}Backup written:${N} $out  ($(du -h "$out" | cut -f1))"
  info "Copy this file out of the machine (USB stick, course cloud folder): a backup that stays inside the machine is lost with it."
}

# -------------------------------------------------------------------------------------
#  it505 restore FILE — bring back the databases and files of a backup
# -------------------------------------------------------------------------------------
cmd_restore() {
  # The backup file to restore, and working variables.
  local file="${1:-}" tmp d db
  # Stop with a usage line if the file cannot be read.
  [ -r "$file" ] || { info "Usage: it505 restore /path/to/it505-backup-....tar.gz"; return 2; }
  # Unpack the backup into a temporary folder; stop if it is not a valid archive.
  tmp="$(mktemp -d)"; tar -xzf "$file" -C "$tmp" || { info "${R}This file is not a readable backup.${N}"; return 1; }
  # Print the title and the description that the backup carries.
  info "${B}IT 505 restore${N} from $(basename "$file")"; [ -r "$tmp/MANIFEST.txt" ] && sed 's/^/  | /' "$tmp/MANIFEST.txt"
  # 1. Databases: create each one if it is missing, then load the dump over it.
  for d in "$tmp"/db/*.dump; do
    # Skip the loop if the backup holds no database.
    [ -e "$d" ] || continue
    # The name of the database is the file name without its ending.
    db="$(basename "$d" .dump)"
    # Create the database if it does not exist yet.
    PGDB=postgres pg -c "SELECT 1 FROM pg_database WHERE datname = '$db'" 2>/dev/null | grep -q 1 || PGDB=postgres pg -c "CREATE DATABASE \"$db\" OWNER $PGUSER_IT505" >/dev/null
    # --clean --if-exists replaces objects that exist already; --no-owner gives everything to the course role.
    if pg_restore -h localhost -U "$PGUSER_IT505" --clean --if-exists --no-owner -d "$db" "$d" 2>"$tmp/err"; then info "  database $db restored"
    # pg_restore reported messages: show how many and the first one.
    else info "  ${Y}database $db restored with messages:${N} $(grep -c . "$tmp/err") line(s); first: $(head -n 1 "$tmp/err")"; fi
  done
  # 2. Files: put them back below the home folder; a file of the same name is replaced.
  [ -r "$tmp/files.tar" ]   && tar -xf "$tmp/files.tar" -C "$HOME"   && info "  course folder restored"
  # Put the DBeaver scripts back if the backup contains them.
  [ -r "$tmp/dbeaver.tar" ] && tar -xf "$tmp/dbeaver.tar" -C "$HOME" && info "  DBeaver scripts restored (restart DBeaver to see them)"
  # Delete the temporary folder.
  rm -rf "$tmp"
  # Confirm the end and name the command that checks the result.
  info "${G}Restore finished.${N} Check with: it505 status"
}

# -------------------------------------------------------------------------------------
#  it505 audit — the hardening checks of Guide 2
# -------------------------------------------------------------------------------------
cmd_audit() {
  # Run the check of the hardening script if that script was installed.
  if [ -x /usr/local/sbin/it505-harden ]; then sudo /usr/local/sbin/it505-harden --check
  # Otherwise say how to run the hardening first.
  else info "The hardening script has not been run on this machine yet (Guide 2, step 5): sudo bash it505_harden.sh"; return 1; fi
}

cmd_help() {
  # Print the help text that follows, up to the line EOF.
  cat <<EOF
${B}it505${N} $VERSION — helper command of the IT 505 lab machine

  it505 status               what is installed and what is running
  it505 selftest             prove that every database family of the course works
  it505 notebook             open JupyterLab in the folder $IT505_HOME
  it505 start NAME           start a service: postgresql | valkey   (also: stop, restart)
  it505 demo list            demonstration engines in containers (CouchDB, FerretDB, Neo4j, Cassandra, Geth)
  it505 backup [FOLDER]      save databases + course folder + DBeaver scripts in one file
  it505 restore FILE         bring a backup file back
  it505 audit                repeat the hardening checks of Guide 2
  it505 help                 this text

Course folder: $IT505_HOME      Database: $PGDB_IT505 on localhost:5432, user $PGUSER_IT505
Legal notice:  https://cyber-soho.github.io/prevmon/00.01.%20cyber.soho%20-%20legal.html
EOF
}

# ---- choose the sub-command ----
case "${1:-help}" in
  status)                 cmd_status ;;   # overview of the machine
  selftest|test)          cmd_selftest ;;   # prove that every tool works
  notebook|jupyter|lab)   cmd_notebook ;;   # start JupyterLab
  start|stop|restart)     cmd_service "$1" "${2:-}" ;;   # start, stop or restart a server
  demo)                   shift; cmd_demo "$@" ;;   # demonstration engines
  backup)                 shift; cmd_backup "$@" ;;   # write a backup
  restore)                shift; cmd_restore "$@" ;;   # load a backup
  audit)                  cmd_audit ;;   # check of the hardening
  help|-h|--help)         cmd_help ;;   # show the help
  *)                      info "Unknown sub-command '$1'."; cmd_help; exit 2 ;;   # unknown word: say so, show the help, report an error
esac
IT505_HELPER_EOF
  # Everybody may run the helper; only root may change it.
  chmod 0755 /usr/local/bin/it505
  # Show how to call it.
  say "  helper command installed: it505 help"
}

# ---- 10. podman for the demonstration engines ----
step_demo() {
  # podman runs containers without a permanently running administrator service; recommended packages are needed here
  # because they provide the networking and user mapping of containers started by a regular account.
  have podman || { say "  installing: podman"; DEBIAN_FRONTEND=noninteractive quiet apt-get -o DPkg::Lock::Timeout=600 install -y -q podman; }
  # Show the version of podman and how the engines are used.
  say "  podman $(podman --version 2>/dev/null | awk '{print $3}') — engines are downloaded at their first start: it505 demo list"
}

# ---- 11. extras: MariaDB and R ----
step_extras() {
  # MariaDB: the other open-source relational server named in Class 4. It is installed but not started automatically.
  have mariadb || apt_install mariadb-server
  # Do not let MariaDB run all the time: it is needed only for one comparison in class.
  if have_systemd; then systemctl disable --now mariadb >/dev/null 2>&1 || true; fi
  # R with the database interface DBI and a PostgreSQL driver, for students who prefer R in Class 10.
  apt_install r-base-core r-cran-dbi || true
  # The driver that connects R to PostgreSQL: try the two package names, otherwise say how to install it inside R.
  apt_install r-cran-rpostgres || apt_install r-cran-rpostgresql || say "  ${Y}no packaged R driver for PostgreSQL was found; install.packages('RPostgres') inside R is the alternative${N}"
  # Show what was installed.
  say "  MariaDB (start with: sudo systemctl start mariadb) and R $(R --version 2>/dev/null | sed -n '1s/R version \([0-9.]*\).*/\1/p')"
}

# ---- 12. cloud profile: services reachable from your own computer ----
step_cloud() {
  # Port and version of the PostgreSQL server, as noted by the earlier step.
  local port ver; port="$(cat "$STATE/pg_port" 2>/dev/null || echo 5432)"; ver="$(cat "$STATE/pg_version" 2>/dev/null)"
  # a) Security updates install themselves.
  apt_install unattended-upgrades || true
  # Switch on the daily installation of security updates.
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' >/etc/apt/apt.conf.d/20auto-upgrades
  # b) Remote login only with a key file, never with a password, and never as root.
  if [ -d /etc/ssh/sshd_config.d ]; then
    # Remote login only with a key file: never with a password, never as root.
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' >/etc/ssh/sshd_config.d/60-it505.conf
    # Let the SSH server read the new rule.
    if have_systemd; then systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true; fi
  fi
  # c) PostgreSQL accepts the course role from outside, only through an encrypted (TLS) connection and with its password.
  if [ "$(runuser -u postgres -- psql -p "$port" -XAtc 'SHOW ssl' 2>/dev/null)" = "on" ]; then
    # Let PostgreSQL listen on every network address of the machine.
    runuser -u postgres -- psql -p "$port" -X -q -c "ALTER SYSTEM SET listen_addresses = '*'"
    # Find the file that decides who may connect.
    local hba; hba="$(runuser -u postgres -- psql -p "$port" -XAtc 'SHOW hba_file')"
    # Add one rule, once: the role it505 may connect from other machines, only encrypted and with its password.
    grep -q 'it505-cloud' "$hba" || printf '\n# it505-cloud: the course role may connect from other machines, only through TLS and with its password\nhostssl all it505 0.0.0.0/0 scram-sha-256\n' >>"$hba"
    # Restart the server so that both changes take effect.
    if have_systemd; then systemctl restart postgresql; else pg_ctlcluster "$ver" main restart </dev/null >/dev/null 2>&1; fi
    # Say what is now possible, and who decides about it.
    say "  PostgreSQL accepts encrypted connections of the role it505 from other machines (the AWS security group decides which)"
  else
    # Without a certificate the server stays closed to other machines: say so.
    say "  ${Y}PostgreSQL has no TLS certificate here, so it stays reachable from this machine only${N}"
  fi
  # d) JupyterLab as a service: encrypted with a certificate made on this machine, protected by a password.
  as_user mkdir -p "$HOME_DIR/.jupyter"
  # Create a certificate for JupyterLab once; later runs keep it, so that the browser shows its warning only once.
  if [ ! -s "$HOME_DIR/.jupyter/it505.key" ]; then
    # A self-signed certificate: it encrypts the connection, but browsers warn because no authority has confirmed it.
    as_user openssl req -x509 -newkey rsa:2048 -nodes -days 180 -subj "/CN=it505-lab" -keyout "$HOME_DIR/.jupyter/it505.key" -out "$HOME_DIR/.jupyter/it505.crt" 2>/dev/null
    # The private key is readable by its owner only.
    chmod 600 "$HOME_DIR/.jupyter/it505.key"
  fi
  # Store only a salted hash of the password, never the password itself.
  local hash; hash="$("$VENV/bin/python" -c 'import sys; from jupyter_server.auth import passwd; print(passwd(sys.argv[1]))' "$JUPYTER_PASSWORD")"
  # Write the settings of JupyterLab (the text up to the line EOF).
  cat >"$HOME_DIR/.jupyter/jupyter_server_config.json" <<EOF
{
  "ServerApp": {"ip": "0.0.0.0", "port": 8888, "open_browser": false, "root_dir": "$COURSE_DIR",
                "certfile": "$HOME_DIR/.jupyter/it505.crt", "keyfile": "$HOME_DIR/.jupyter/it505.key"},
  "IdentityProvider": {"token": ""},
  "PasswordIdentityProvider": {"hashed_password": "$hash"}
}
EOF
  # The settings belong to the user; the file holds the hash of a password, so nobody else may read it.
  chown -R "$TARGET_USER": "$HOME_DIR/.jupyter"; chmod 600 "$HOME_DIR/.jupyter/jupyter_server_config.json"
  # Describe JupyterLab as a service that systemd starts at every boot (the text up to the line EOF).
  cat >/etc/systemd/system/it505-jupyter.service <<EOF
[Unit]
Description=IT 505 JupyterLab (course folder $COURSE_DIR)
After=network-online.target postgresql.service
[Service]
User=$TARGET_USER
WorkingDirectory=$COURSE_DIR
Environment=PATH=$VENV/bin:/usr/local/bin:/usr/bin:/bin
Environment=PGHOST=localhost PGUSER=it505 PGDATABASE=mercadillo
ExecStart=$VENV/bin/jupyter lab
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  # Let systemd read the new service, then start it now and at every boot.
  if have_systemd; then systemctl daemon-reload; systemctl enable --now it505-jupyter.service >/dev/null 2>&1 || true; fi
  # e) One file with every address and password of this machine, readable only by its user.
  ( umask 077; cat >"$COURSE_DIR/ACCESS.txt" <<EOF
IT 505 cloud machine — addresses and passwords (keep this file private)
Written by it505_setup.sh on $(date '+%d %B %Y %H:%M').

The public address of the machine changes every time it is started.
In AWS CloudShell, the command   bash it505_aws.sh status   prints the current one.

JupyterLab : https://PUBLIC-ADDRESS:8888      password: $JUPYTER_PASSWORD
             (the browser warns about the certificate once: Advanced > Proceed)
PostgreSQL : host PUBLIC-ADDRESS   port $port   database mercadillo   user it505   password: $PG_PASSWORD
             (in DBeaver: connection type PostgreSQL; the connection is encrypted with TLS)
Terminal   : in CloudShell:  bash it505_aws.sh ssh
EOF
  )
  # The access card belongs to the user.
  chown "$TARGET_USER": "$COURSE_DIR/ACCESS.txt"
  # Show where the addresses and passwords are.
  say "  JupyterLab service on port 8888; addresses and passwords: $COURSE_DIR/ACCESS.txt"
}

# ---- 13. cloud profile, optional: a remote desktop with DBeaver ----
step_desktop() {
  # lxqt-core: the LXQt desktop without office programs. xfwm4: a window manager. xrdp + xorgxrdp: the remote-desktop server.
  apt_install lxqt-core xfwm4 xrdp xorgxrdp dbus-x11 qterminal featherpad firefox-esr || apt_install lxqt-core xfwm4 xrdp xorgxrdp dbus-x11 qterminal featherpad
  # Tell the remote-desktop session to start LXQt.
  as_user sh -c "echo startlxqt > '$HOME_DIR/.xsession'"
  # The remote-desktop server needs a password for the account; remote login by SSH still accepts key files only.
  echo "$TARGET_USER:$PG_PASSWORD" | chpasswd
  # xrdp must be allowed to read the machine's TLS certificate.
  adduser xrdp ssl-cert >/dev/null 2>&1 || true
  # Start the remote-desktop server now and at every boot.
  if have_systemd; then systemctl enable --now xrdp >/dev/null 2>&1 || true; fi
  # Explain how to connect to the desktop.
  printf '\nRemote desktop: connect a Remote Desktop (RDP) client to PUBLIC-ADDRESS, port 3389   user: %s   password: the PostgreSQL password above\n' "$TARGET_USER" >>"$COURSE_DIR/ACCESS.txt"
  say "  remote desktop (xrdp) on port 3389 for the account $TARGET_USER"
}

# =====================================================================================
#  Run the steps: each one in its own sub-shell, so that a failure is recorded and the rest continues
# =====================================================================================
PLAN=("Basic tools (curl, git, SQLite, Python)|step_base"
      "PostgreSQL $PG_VERSION: server, role it505, database mercadillo|step_postgres"   # the relational server of the course
      "Python environment: JupyterLab, pandas, SQLAlchemy, DuckDB|step_python"   # the notebook and the analysis libraries
      "DuckDB command-line client|step_duckdb")
# DBeaver needs a desktop: the local virtual machine has one, the cloud twin only with --desktop.
if [ "$PROFILE" = "vm" ] || [ "$DESKTOP" -eq 1 ]; then PLAN+=("DBeaver Community (graphical SQL client)|step_dbeaver"); fi
# Valkey and Spark belong to Lab 3 and the class demonstrations; a core-only installation leaves them out.
if [ "$COMPONENTS" = "labs" ]; then PLAN+=("Valkey (key-value store)|step_valkey" "Apache Spark (PySpark) with Java 21|step_spark"); fi
# The course folder and the helper command close every installation.
PLAN+=("Course folder and lab settings|step_course_folder" "Helper command it505|step_helper")
# Optional: podman.
[ "$WITH_DEMO" -eq 1 ]   && PLAN+=("podman for the demonstration engines|step_demo")
# Optional: MariaDB and R.
[ "$WITH_EXTRAS" -eq 1 ] && PLAN+=("Extras: MariaDB and R|step_extras")
# The cloud twin opens JupyterLab and PostgreSQL to the address of the student.
[ "$PROFILE" = "cloud" ] && PLAN+=("Cloud services: JupyterLab over HTTPS, PostgreSQL over TLS|step_cloud")
# Optional on the cloud twin: a remote desktop.
if [ "$PROFILE" = "cloud" ] && [ "$DESKTOP" -eq 1 ]; then PLAN+=("Remote desktop (xrdp with LXQt)|step_desktop"); fi

# Start an empty list of results.
: >"$STATE/steps"
# Counters for the progress line and for the total time.
STEP_NO=0; STEP_TOTAL="${#PLAN[@]}"; T_START=$SECONDS
# Run the steps of the plan one after the other.
for entry in "${PLAN[@]}"; do
  # Split the entry into its title and the name of its function; note the start time.
  title="${entry%%|*}"; fn="${entry##*|}"; STEP_NO=$((STEP_NO + 1)); t0=$SECONDS
  printf '\n%s[%s/%s] %s%s\n' "$B" "$STEP_NO" "$STEP_TOTAL" "$title" "$N"
  # "set -e" inside the sub-shell stops the step at its first failing command; the script itself carries on.
  ( set -e; "$fn" ); rc=$?
  # Success: note it with its duration.
  if [ "$rc" -eq 0 ]; then printf '%s|OK|%s\n' "$title" "$((SECONDS - t0))" >>"$STATE/steps"; printf '  %sdone in %s s%s\n' "$G" "$((SECONDS - t0))" "$N"
  # Failure: note it, say so, and go on with the next step.
  else printf '%s|FAILED|%s\n' "$title" "$((SECONDS - t0))" >>"$STATE/steps"; printf '  %sthis step failed; the installer continues with the next one%s\n' "$R" "$N"; fi
done

# =====================================================================================
#  The result table
# =====================================================================================
FAILED_STEPS="$(grep -c '|FAILED|' "$STATE/steps" || true)"
# Print the heading of the result table.
printf '\n%s%s%s\n' "$B" "Result of the installation" "$N"
# One line per step: OK or FAIL, the title, the duration.
while IFS='|' read -r title result secs; do
  # Green for OK, red for FAIL.
  if [ "$result" = "OK" ]; then printf '  %s[ OK ]%s   %-62s %4s s\n' "$G" "$N" "$title" "$secs"; else printf '  %s[FAIL]%s   %-62s %4s s\n' "$R" "$N" "$title" "$secs"; fi
done <"$STATE/steps"   # the loop reads the results noted above
# Print the total time and the place of the log.
printf '  Total time: %s min %s s. Log: %s\n' "$(((SECONDS - T_START) / 60))" "$(((SECONDS - T_START) % 60))" "$LOG"
# Note the date of this installation.
date '+%d %B %Y %H:%M' >"$STATE/installed"

# From here on the output goes to the screen only: the next line may show a password, which must not be written to the log.
finish
# A password that the installer created itself must be shown, or nobody would know it.
if [ "$PG_PASSWORD_GENERATED" -eq 1 ]; then
  # Show it, and say where it is stored.
  printf '\n%sPassword of the database user it505: %s%s   (also stored in %s/.pgpass)\n' "$B" "$PG_PASSWORD" "$N" "$HOME_DIR"
fi
# Close with the next step for the user: prove it, or repeat the run.
if [ "$FAILED_STEPS" -eq 0 ]; then
  # Everything worked: name the self-test.
  printf '\n%s%sEverything is installed.%s Open a NEW terminal and prove it:  %sit505 selftest%s\n' "$G" "$B" "$N" "$B" "$N"
else
  # Something failed: say how to repeat the run.
  printf '\n%s%s%s step(s) failed.%s Check the internet connection and run the same command again; finished steps are not repeated.\n' "$R" "$B" "$FAILED_STEPS" "$N"
fi
# Mark the end for programs that wait for this installer (it505_aws.sh does).
printf '%s\n' "$FAILED_STEPS" >"$STATE/setup.done"
# The exit code is the number of failed steps, so that other scripts can test it.
exit "$FAILED_STEPS"
