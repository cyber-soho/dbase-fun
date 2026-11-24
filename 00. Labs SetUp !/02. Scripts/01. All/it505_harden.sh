#!/usr/bin/env bash
# =====================================================================================
#  it505_harden.sh — hardening of the IT 505 lab virtual machine
#  IT 505 · Fundamentals of Database Technologies · Cyber.SoHo Educational Hub
#  Version 1.0 (21 November 2026)
#
#  Target : Debian 13 "trixie" with the LXQt desktop, inside VirtualBox.
#           It also runs on Ubuntu 24.04 / 26.04 and their LXQt edition (Lubuntu).
#  Usage  : sudo bash it505_harden.sh            apply the nine settings, then check them
#           sudo bash it505_harden.sh --check    only check; nothing is changed
#           sudo bash it505_harden.sh --keep-ssh keep a remote-login (SSH) server if one is installed
#
#  "Hardening" means reducing what can go wrong on a machine: fewer programs that listen
#  on the network, updates that install themselves, and settings that refuse unsafe input.
#  Every tool used here is open-source software. Each one can be replaced by another
#  suitable tool if you can justify the choice; research the alternatives.
#  Legal notice: https://cyber-soho.github.io/prevmon/00.01.%20cyber.soho%20-%20legal.html
# =====================================================================================

# Stop on the use of an unset variable; a failed command is handled step by step below.
set -u

# ---- options given on the command line ----
# CHECK_ONLY=1 means "look, but change nothing".
CHECK_ONLY=0
# KEEP_SSH=1 means "do not switch off an SSH (Secure Shell) server".
KEEP_SSH=0
# Read the options given on the command line, one after the other.
for arg in "$@"; do
  case "$arg" in
    --check)    CHECK_ONLY=1 ;;   # only check, change nothing
    --keep-ssh) KEEP_SSH=1 ;;   # leave a remote-login server running
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;   # print the explanation at the top of this file, then stop
    *) echo "Unknown option: $arg (try --help)"; exit 2 ;;   # anything else is a typing mistake: say so and stop
  esac
done

# ---- colours, only when the output is a terminal ----
if [ -t 1 ]; then G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'; else G=""; Y=""; B=""; N=""; fi
# Counters for the final line of the check.
PASSED=0; WARNED=0
# Print a green PASS line and count it.
pass() { printf '  %s[PASS]%s %s\n' "$G" "$N" "$*"; PASSED=$((PASSED + 1)); }
# Print a yellow WARN line and count it.
warn() { printf '  %s[WARN]%s %s\n' "$Y" "$N" "$*"; WARNED=$((WARNED + 1)); }
# Print the title of a step in bold type.
step() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
# True when the named program is installed.
have() { command -v "$1" >/dev/null 2>&1; }
# True when this machine is managed by systemd (the normal case on Debian and Ubuntu).
have_systemd() { [ -d /run/systemd/system ]; }

# The script changes system settings, so it must run as the administrator account "root" (through sudo).
if [ "$(id -u)" -ne 0 ]; then echo "Please run this script with sudo:  sudo bash $0 $*"; exit 1; fi

# The person who called sudo; this is the account that must keep its administrator rights.
LAB_USER="${SUDO_USER:-$(getent passwd 1000 | cut -d: -f1)}"
# A folder for small notes about what was done, shared with it505_setup.sh.
STATE=/var/lib/it505
# Create the folder in which this script keeps its own notes.
mkdir -p "$STATE"
# The file in which this script stores its kernel network settings.
SYSCTL_FILE=/etc/sysctl.d/60-it505-hardening.conf
# Network services that a lab machine does not need: printing, device discovery, Bluetooth, mobile modems.
UNNEEDED_UNITS="cups.service cups.socket cups.path cups-browsed.service avahi-daemon.service avahi-daemon.socket bluetooth.service ModemManager.service"

# Install packages without asking questions; --no-install-recommends keeps the machine small.
# -o DPkg::Lock::Timeout=300: if the automatic update is installing packages at this moment, wait for it up to five minutes.
apt_install() { DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends "$@" >/dev/null; }

# =====================================================================================
#  PART 1 — apply the settings (skipped with --check)
# =====================================================================================
apply_all() {
  # Step 1: say on the screen what is about to happen.
  step "1/9  Bring every installed package up to date"
  # Read the current package lists from the Debian servers.
  apt-get update -qq || echo "  (the package lists could not be refreshed; check the internet connection)"
  # Install every available update, including those that replace or remove a package.
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -y -qq full-upgrade || echo "  (some updates could not be installed)"

  # Step 2: say on the screen what is about to happen.
  step "2/9  Let security updates install themselves every day"
  # unattended-upgrades downloads and installs security updates without a person at the keyboard.
  apt_install unattended-upgrades apt-listchanges || echo "  (unattended-upgrades could not be installed)"
  # These two lines switch the daily refresh and the daily unattended upgrade on.
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' >/etc/apt/apt.conf.d/20auto-upgrades

  # Step 3: say on the screen what is about to happen.
  step "3/9  Firewall: refuse incoming connections, allow outgoing ones"
  # ufw (Uncomplicated Firewall) is a simple front end to the packet filter of the Linux kernel.
  apt_install ufw || echo "  (ufw could not be installed)"
  # Configure the firewall only if the program ufw is present.
  if have ufw; then
    # Nothing outside this machine may open a connection to it ...
    ufw default deny incoming >/dev/null
    # ... while the machine itself may still reach the internet (updates, downloads, the course site).
    ufw default allow outgoing >/dev/null
    # Switch the firewall on now and at every start; --force answers the confirmation question.
    ufw --force enable >/dev/null || echo "  (the firewall could not be switched on here)"
  fi

  # Step 4: say on the screen what is about to happen.
  step "4/9  Switch off network services that a lab machine does not need"
  # Services can be switched off only where systemd manages them.
  if have_systemd; then
    # Go through the list of services that a lab machine does not need.
    for unit in $UNNEEDED_UNITS; do
      # Only touch a service that really exists on this machine.
      if systemctl list-unit-files "$unit" 2>/dev/null | grep -q "^$unit"; then
        # "disable --now" stops the service immediately and keeps it from starting again.
        systemctl disable --now "$unit" >/dev/null 2>&1 && echo "  switched off: $unit"
      fi
    done
  fi

  # Step 5: say on the screen what is about to happen.
  step "5/9  Remote login (SSH) server"
  # Is an SSH server installed at all?
  if have_systemd && systemctl list-unit-files ssh.service 2>/dev/null | grep -q '^ssh.service'; then
    # If the user asked to keep it, leave it running.
    if [ "$KEEP_SSH" -eq 1 ]; then echo "  kept, as requested with --keep-ssh"
    # Otherwise stop it now and keep it from starting at the next boot.
    else systemctl disable --now ssh.service ssh.socket >/dev/null 2>&1; echo "  an SSH server was installed; it is now switched off (nobody logs in to this machine remotely)"; fi
  # Nothing is installed, so nothing has to be switched off.
  else echo "  no SSH server is installed: nothing to do"; fi

  # Step 6: say on the screen what is about to happen.
  step "6/9  The administrator account root cannot log in with a password"
  # Lock root only if your own account can use sudo; otherwise you would lock yourself out.
  if [ -n "$LAB_USER" ] && id -nG "$LAB_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
    # "passwd -l" locks the password of root; administration then happens through sudo only.
    passwd -l root >/dev/null && echo "  root password locked; $LAB_USER administers the machine with sudo"
  # Without sudo rights for the lab account, locking root would lock the administrator out: skip the step.
  else echo "  skipped: the account '$LAB_USER' is not in the sudo group, so root stays as it is"; fi

  # Step 7: say on the screen what is about to happen.
  step "7/9  Safer network settings of the kernel"
  # Each line is one setting; the comments say what it refuses.
  cat >"$SYSCTL_FILE" <<'EOF'
# IT 505 lab machine — written by it505_harden.sh
# Refuse packets whose sender address could not be reached through the interface they arrived on.
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Ignore messages that ask this machine to change its routes.
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
# This machine is not a router: it never sends such messages itself.
net.ipv4.conf.all.send_redirects = 0
# Refuse packets that dictate their own route.
net.ipv4.conf.all.accept_source_route = 0
# Stay reachable when many half-open connections arrive at once.
net.ipv4.tcp_syncookies = 1
# Do not answer echo requests sent to a whole network.
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Only the administrator may read kernel messages and kernel memory addresses.
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
EOF
  # Load the file now; without this the settings would only apply after the next start.
  sysctl --system >/dev/null 2>&1 || echo "  (the settings will apply after the next restart)"

  # Step 8: say on the screen what is about to happen.
  step "8/9  Your home folder is private; the desktop asks for your password"
  # Close the home folder only if the lab account and its folder exist.
  if [ -n "$LAB_USER" ] && [ -d "/home/$LAB_USER" ]; then
    # 750 = you may do everything, your group may read, everybody else has no access.
    chmod 750 "/home/$LAB_USER" && echo "  /home/$LAB_USER is now closed to other accounts"
  fi
  # Automatic login would open the desktop without a password; remove it from the login managers SDDM and LightDM.
  for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/*.conf; do
    # Skip a configuration file that does not exist on this system.
    [ -f "$f" ] || continue
    # Does this file switch on automatic login?
    if grep -Eq '^(User=.+|autologin-user=.+)' "$f"; then
      # Keep a copy of the file, then turn the automatic-login lines into comments.
      cp -n "$f" "$f.it505-backup"; sed -i -E 's/^(User=.+|autologin-user=.+)/# \1   (disabled by it505_harden.sh)/' "$f"
      # Tell the user which file was changed.
      echo "  automatic login removed from $f"
    fi
  done

  # Step 9: say on the screen what is about to happen.
  step "9/9  Record the date of this hardening"
  # Write the date and time into the notes folder, so that the check can show when the machine was hardened.
  date '+%d %B %Y %H:%M' >"$STATE/hardened"
  # Keep a copy of this script where the command "it505 audit" expects it.
  install -m 0755 "$0" /usr/local/sbin/it505-harden 2>/dev/null && echo "  check again at any time with: sudo it505-harden --check"
}

# =====================================================================================
#  PART 2 — check the settings (always runs)
# =====================================================================================
check_all() {
  # Print the heading of the check with the current date and time.
  step "Hardening check of this machine — $(date '+%d %B %Y %H:%M')"

  # 1. No update is waiting.
  local pending; pending="$(apt-get -s -o Debug::NoLocking=true upgrade 2>/dev/null | grep -c '^Inst ')"
  # Pass when no update is waiting; otherwise say how many and how to install them.
  if [ "$pending" -eq 0 ]; then pass "No update is waiting to be installed"; else warn "$pending update(s) waiting: run  sudo apt update && sudo apt full-upgrade"; fi

  # 2. Unattended security updates are switched on.
  if grep -qs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades && dpkg -s unattended-upgrades >/dev/null 2>&1; then pass "Security updates install themselves every day (unattended-upgrades)"
  # Otherwise report it as an open point.
  else warn "Automatic security updates are not switched on"; fi

  # 3. The firewall is active with the expected default rules.
  if have ufw && ufw status verbose 2>/dev/null | grep -q '^Status: active' && ufw status verbose 2>/dev/null | grep -q 'deny (incoming)'; then pass "Firewall is on: incoming connections refused, outgoing allowed"
  # Otherwise report it as an open point.
  else warn "The firewall (ufw) is not active"; fi

  # 4. None of the unneeded services is running.
  local running="" unit
  # Collect the names of the unneeded services that are still running.
  if have_systemd; then for unit in $UNNEEDED_UNITS; do systemctl is-active --quiet "$unit" 2>/dev/null && running="$running $unit"; done; fi
  # Pass when that list is empty; otherwise name the services.
  if [ -z "$running" ]; then pass "Printing, device discovery, Bluetooth and modem services are off"; else warn "Still running:$running"; fi

  # 5. No SSH server is listening.
  if have_systemd && systemctl is-active --quiet ssh.service 2>/dev/null; then
    # A running SSH server passes only if the user asked to keep it.
    if [ "$KEEP_SSH" -eq 1 ]; then pass "An SSH server is running, as requested with --keep-ssh"; else warn "An SSH server is running; switch it off unless you need remote login"; fi
  # No SSH server is running: pass.
  else pass "No remote-login (SSH) server is running"; fi

  # 6. The root password is locked (the status letter L) or was never set (NP).
  case "$(passwd -S root 2>/dev/null | awk '{print $2}')" in
    L|LK|NP) pass "The root account has no usable password; administration goes through sudo" ;;   # L, LK or NP: the password of root is locked or absent
    *) warn "The root account can log in with a password" ;;   # any other state: root can log in with a password
  esac

  # 7. The kernel network settings are in force.
  if [ -f "$SYSCTL_FILE" ] && [ "$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)" = "0" ] && [ "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)" = "1" ]; then pass "Kernel network settings refuse redirects and source-routed packets"
  # Otherwise report it as an open point.
  else warn "The kernel network settings of step 7 are not in force"; fi

  # 8. AppArmor confines programs to the files they need; Debian and Ubuntu switch it on by default.
  if [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" = "Y" ]; then pass "AppArmor is enabled (programs are confined to the files they need)"
  # Otherwise report it as an open point.
  else warn "AppArmor is not enabled"; fi

  # 9. The desktop does not log in automatically.
  if grep -Eqs '^(User=.+|autologin-user=.+)' /etc/sddm.conf /etc/sddm.conf.d/*.conf /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/*.conf 2>/dev/null; then warn "The desktop logs in without a password (automatic login)"
  # No automatic login was found: pass.
  else pass "The desktop asks for your password at every start"; fi

  # 10. Nothing listens on a network address that other machines can reach, except the address service (DHCP client, port 68).
  local open; open="$(ss -H -tuln 2>/dev/null | awk '{print $1" "$5}' | grep -Ev '(127\.0\.0\.[0-9]+|\[::1\]|%lo):' | grep -Ev ':(68|546)$' | sort -u | tr '\n' ';')"
  # Pass when nothing listens for other machines.
  if [ -z "$open" ]; then pass "No program listens for connections from other machines"
  # Otherwise show what is listening.
  else warn "Listening for other machines: $open (expected only on the cloud machine)"; fi

  # Print the summary: how many of the checks passed.
  printf '\n%sResult: %s of %s checks passed.%s' "$B" "$PASSED" "$((PASSED + WARNED))" "$N"
  # Add the verdict: hardened, or read the warnings.
  if [ "$WARNED" -eq 0 ]; then printf ' %sThe machine is hardened for the course.%s\n' "$G" "$N"; else printf ' %sRead the lines marked WARN.%s\n' "$Y" "$N"; fi
}

# ---- run ----
if [ "$CHECK_ONLY" -eq 0 ]; then
  # Print the title of the run and the account that is being protected.
  printf '%sIT 505 — hardening the lab machine%s (account: %s)\n' "$B" "$N" "${LAB_USER:-unknown}"
  # Apply the nine settings.
  apply_all
fi
# Run the ten checks: after the settings were applied, and also when only --check was asked for.
check_all
# The exit code is the number of warnings, so that other scripts can react to it.
exit "$WARNED"
