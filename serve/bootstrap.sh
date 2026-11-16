#!/usr/bin/env bash
#
# Bootstrap Script - Ubuntu 24.04 VM/LXC Setup
#
# Usage (from a fresh Ubuntu 24.04 VM - use the LAN IP of the bootstrap server):
#   curl -fS http://<server-ip>:9090/bootstrap.sh -o /tmp/bootstrap.sh && sudo bash /tmp/bootstrap.sh --server http://<server-ip>:9090 --role vm
#
# Roles: vm | lxc-host | lxc-container | security | docker | minimal
#

set -euo pipefail

# === LOGGING =================================================
# Capture every byte of stdout+stderr to a log file so the user can re-read
# the output if their terminal/SSH console buffered it away.
LOG_DIR="/var/log/bootstrap"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Trap unexpected exits so the user sees an error instead of nothing
trap 'rc=$?; echo ""; echo "  [FATAL] Script died unexpectedly at line $LINENO (exit code $rc)"; echo "  Full log: $LOG_FILE"; echo "  Re-run with: bash -x $0 --server <url> --role <role>"' ERR

BOOTSTRAP_DIR="/opt/bootstrap"
SERVER_URL="${BOOTSTRAP_SERVER_URL:-}"
ROLE="vm"
EXTRA_ARGS=""
VERBOSE=false
SKIP_INSTALL=false

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --role) ROLE="$2"; shift 2 ;;
        --server) SERVER_URL="$2"; shift 2 ;;
        --dir) BOOTSTRAP_DIR="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --tags) EXTRA_ARGS="$EXTRA_ARGS --tags $2"; shift 2 ;;
        --skip-install) SKIP_INSTALL=true; shift ;;
        --help|-h)
            echo "Usage: bootstrap.sh --role <vm|lxc-host|lxc-container|security|docker|minimal>"
            echo "       [--server URL] [--dir PATH] [--tags TAGS] [--verbose]"
            exit 0 ;;
        *) EXTRA_ARGS="$EXTRA_ARGS $1"; shift ;;
    esac
done

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
log()  { echo -e "${CYAN}[bootstrap]${NC} $*"; }
ok()   { echo -e "${GREEN}  +${NC} $*"; }
warn() { echo -e "${YELLOW}  !${NC} $*"; }
err()  { echo -e "${RED}  x${NC} $*"; }
banner() {
    echo -e "\n${BOLD}${CYAN}==========================================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}${CYAN}==========================================================${NC}\n"
}

# Validate
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)"; exit 1
fi
if [[ -z "$SERVER_URL" ]]; then
    err "Server URL not specified. Use --server http://<your-ip>:9090"; exit 1
fi
case "$ROLE" in
    vm|lxc-host|lxc-container|security|docker|minimal) ;;
    *) err "Unknown role: $ROLE"; exit 1 ;;
esac
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        warn "Not Ubuntu (detected: ${ID:-unknown})"
    fi
    if [[ "${VERSION_ID:-}" != "24.04" ]]; then
        warn "Not 24.04 (detected: ${VERSION_ID:-unknown})"
    fi
fi

banner "Bootstrap Setup - Role: $ROLE"

# === WHAT WILL BE CONFIGURED (per role) ====================
case "$ROLE" in
    vm)
        COMPONENTS=(
            "Base packages (htop, vim, git, etc.)"
            "Unattended upgrades"
            "Timezone + locale"
            "Network hardening (sysctl + IP forwarding)"
            "SSH hardening (root keys only; passwords off once an SSH key exists)"
            "Firewall disabled (UFW off)"
            "Fail2ban"
            "Docker CE + compose"
        ) ;;
    lxc-host)
        COMPONENTS=(
            "Base packages (htop, vim, git, etc.)"
            "Unattended upgrades"
            "Timezone + locale"
            "Network hardening (sysctl + IP forwarding)"
            "SSH hardening (root keys only; passwords off once an SSH key exists)"
            "Firewall disabled (UFW off)"
            "Fail2ban"
            "LXC host tooling + bridge networking"
        ) ;;
    lxc-container)
        COMPONENTS=(
            "Base packages only (htop, vim, git)"
        ) ;;
    security)
        COMPONENTS=(
            "SSH hardening (root keys only; passwords off once an SSH key exists)"
            "Firewall disabled (UFW off)"
            "Fail2ban"
        ) ;;
    docker)
        COMPONENTS=(
            "Docker CE + compose"
        ) ;;
    minimal)
        COMPONENTS=(
            "Base packages (htop, vim, git)"
            "Unattended upgrades"
            "Timezone + locale"
        ) ;;
esac

log "ROLE = $ROLE - will configure:"
for c in "${COMPONENTS[@]}"; do
    printf "        + %s\n" "$c"
done
case "$ROLE" in
    minimal|lxc-container)
        warn "This role does NOT install Docker or fail2ban, or harden SSH."
        warn "Use --role vm for a full setup."
        ;;
esac
echo ""

log "Server:      $SERVER_URL"
log "Install dir: $BOOTSTRAP_DIR"
log "Log file:    $LOG_FILE"
echo ""
log "If output scrolls away in your terminal, re-read it any time with:"
log "    cat $LOG_FILE"
log "Or follow it live from another terminal:"
log "    tail -f $LOG_FILE"
echo ""

# Quick connectivity check (fail fast, don't hang silently)
log "Testing connectivity to $SERVER_URL ..."
if ! curl -fsS --connect-timeout 5 --max-time 10 "$SERVER_URL/api/health" >/dev/null 2>&1; then
    err "Cannot reach $SERVER_URL"
    echo ""
    echo "  Debug steps:"
    echo "    curl -v $SERVER_URL/"
    SERVER_HOST="${SERVER_URL#*://}"; SERVER_HOST="${SERVER_HOST%%[:/]*}"
    echo "    ip route get $SERVER_HOST"
    echo ""
    exit 1
fi
ok "Server reachable"

# Check internet access (needed for apt + pip)
log "Checking internet access (for apt and pip)..."
INTERNET_OK=false
for url in http://archive.ubuntu.com/ http://ports.ubuntu.com/ http://google.com/; do
    if curl -fsS --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1; then
        INTERNET_OK=true
        break
    fi
done
if [[ "$INTERNET_OK" != "true" && "$SKIP_INSTALL" == "true" ]]; then
    warn "No internet access - continuing because of --skip-install (apt tasks in the playbook may fail)"
elif [[ "$INTERNET_OK" != "true" ]]; then
    err "No internet access from this machine — apt-get and pip will fail."
    echo ""
    echo "  Fix networking on this VM/LXC first:"
    echo "    - Check gateway: ip route show"
    echo "    - Check DNS:     cat /etc/resolv.conf"
    echo "    - Test:          curl http://archive.ubuntu.com/"
    echo ""
    echo "  If you only need offline setup, re-run with --skip-install"
    echo "  and pre-provision ansible yourself."
    exit 1
else
    ok "Internet reachable"
fi

# Step 1: Install Prerequisites
if [[ "${SKIP_INSTALL}" != "true" ]]; then
    log "Step 1/4: Installing prerequisites (1-3 minutes; apt output may pause)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        curl wget git \
        python3 python3-pip python3-venv python3-dev \
        build-essential libssl-dev libffi-dev \
        rsync tar
    ok "Prerequisites installed"

    # Step 2: Install Ansible via venv (avoids PEP 668 on Ubuntu 24.04)
    log "Step 2/4: Installing Ansible (pip install ansible-core, 1-2 minutes)..."
    ANSIBLE_VENV="/opt/bootstrap-venv"
    if [[ ! -d "$ANSIBLE_VENV" ]]; then
        python3 -m venv "$ANSIBLE_VENV"
    fi
    "$ANSIBLE_VENV/bin/pip" install --upgrade pip
    "$ANSIBLE_VENV/bin/pip" install "ansible-core>=2.16"
    ln -sf "$ANSIBLE_VENV/bin/ansible-playbook" /usr/local/bin/ansible-playbook
    ln -sf "$ANSIBLE_VENV/bin/ansible" /usr/local/bin/ansible
    ln -sf "$ANSIBLE_VENV/bin/ansible-galaxy" /usr/local/bin/ansible-galaxy
    ok "Ansible: $(ansible --version | head -1)"
else
    log "Steps 1-2: Skipping install (--skip-install)"
fi

# Step 3: Download Playbooks
log "Step 3/4: Downloading playbooks from $SERVER_URL..."
mkdir -p "$BOOTSTRAP_DIR"
cd "$BOOTSTRAP_DIR"

fetch() {
    mkdir -p "$(dirname "$1")"
    if ! curl -fsSL --connect-timeout 10 --max-time 60 "$SERVER_URL/$1" -o "$1"; then
        err "Failed to download $SERVER_URL/$1"
        exit 1
    fi
}

for f in \
    "ansible.cfg" \
    "inventory/local.yml" \
    "playbooks/site.yml" \
    "playbooks/vm-setup.yml" \
    "playbooks/lxc-setup.yml" \
    "playbooks/security-only.yml" \
    "roles/common/tasks/main.yml" \
    "roles/common/defaults/main.yml" \
    "roles/security/tasks/main.yml" \
    "roles/security/handlers/main.yml" \
    "roles/security/defaults/main.yml" \
    "roles/network/tasks/main.yml" \
    "roles/network/handlers/main.yml" \
    "roles/docker/tasks/main.yml" \
    "roles/docker/handlers/main.yml" \
    "roles/lxc-host/tasks/main.yml" \
    "roles/lxc-host/handlers/main.yml"; do
    fetch "$f"
done

ok "Playbooks downloaded to $BOOTSTRAP_DIR"

# Step 4: Run Playbook
case "$ROLE" in
    vm)            PLAYBOOK="playbooks/vm-setup.yml" ;;
    lxc-host)      PLAYBOOK="playbooks/lxc-setup.yml" ;;
    lxc-container) PLAYBOOK="playbooks/vm-setup.yml"; EXTRA_ARGS="$EXTRA_ARGS --tags minimal" ;;
    security)      PLAYBOOK="playbooks/security-only.yml" ;;
    docker)        PLAYBOOK="playbooks/vm-setup.yml"; EXTRA_ARGS="$EXTRA_ARGS --tags docker" ;;
    minimal)       PLAYBOOK="playbooks/vm-setup.yml"; EXTRA_ARGS="$EXTRA_ARGS --tags common" ;;
esac

log "Step 4/4: Running Ansible playbook (2-5 minutes; tasks appear as they complete)..."
log "Command: ansible-playbook -i inventory/local.yml $PLAYBOOK $EXTRA_ARGS"
echo ""

VERBOSE_FLAG=""
if [[ "$VERBOSE" == "true" ]]; then
    VERBOSE_FLAG="-vv"
fi

trap - ERR
set +e
ansible-playbook \
    -i "$BOOTSTRAP_DIR/inventory/local.yml" \
    "$BOOTSTRAP_DIR/$PLAYBOOK" \
    $EXTRA_ARGS \
    $VERBOSE_FLAG
ANSIBLE_EXIT=$?

# === FINAL SUMMARY ==========================================
# Always print a visible state-check summary so the user can see what
# actually got configured even if the playbook output scrolled away.
echo ""
banner "Configuration Summary (role used: $ROLE)"

# Determine which components are expected for the chosen role.
# Out-of-scope items show gray "-" instead of red "x" so users don't
# think a minimal run failed because it didn't install Docker, etc.
case "$ROLE" in
    vm)              EXPECTED="docker fail2ban unattended-upgrades htop vim git ssh sysctl" ;;
    lxc-host)        EXPECTED="fail2ban unattended-upgrades htop vim git ssh sysctl lxc" ;;
    lxc-container)   EXPECTED="htop vim git" ;;
    security)        EXPECTED="fail2ban ssh" ;;
    docker)          EXPECTED="docker" ;;
    minimal)         EXPECTED="unattended-upgrades htop vim git" ;;
esac
_in_scope() { [[ " $EXPECTED " == *" $1 "* ]]; }

_check_pkg() {
    local pkg="$1" scope_key="${2:-$1}"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        printf "  ${GREEN}+${NC} %-26s installed\n" "$pkg"
    elif _in_scope "$scope_key"; then
        printf "  ${RED}x${NC} %-26s NOT installed (expected for role %s)\n" "$pkg" "$ROLE"
    else
        printf "  ${DIM}-${NC} %-26s not installed (out of scope for role %s)\n" "$pkg" "$ROLE"
    fi
}

_check_service() {
    local svc="$1" scope_key="${2:-$1}"
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            printf "  ${GREEN}+${NC} %-26s running\n" "$svc"
        elif systemctl list-unit-files "$svc.service" 2>/dev/null | grep -q "$svc"; then
            printf "  ${YELLOW}!${NC} %-26s installed but not running\n" "$svc"
        else
            printf "  ${DIM}-${NC} %-26s not present\n" "$svc"
        fi
    fi
}

_check_pkg docker-ce docker
_check_pkg fail2ban fail2ban
_check_pkg unattended-upgrades unattended-upgrades
_check_pkg htop htop
_check_pkg vim vim
_check_pkg git git
_check_service docker docker
_check_service fail2ban fail2ban
_check_service ssh ssh
if _in_scope lxc; then
    _check_pkg lxc lxc
    _check_service lxc-net lxc
fi

if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1 | sed 's/^Status: //')
    printf "  ${CYAN}~${NC} %-26s %s\n" "ufw" "${UFW_STATUS:-unknown}"
fi

if command -v sshd >/dev/null 2>&1 && mkdir -p /run/sshd && SSHD_EFFECTIVE=$(sshd -T 2>/dev/null); then
    # sshd -T prints the effective config, including sshd_config.d drop-ins
    PRL=$(awk '$1 == "permitrootlogin" {print $2}' <<<"$SSHD_EFFECTIVE")
    PA=$(awk '$1 == "passwordauthentication" {print $2}' <<<"$SSHD_EFFECTIVE")
    printf "  ${CYAN}~${NC} %-26s PermitRootLogin=%s PasswordAuth=%s\n" "sshd" "${PRL:-default}" "${PA:-default}"
fi

if [[ -f /etc/sysctl.d/99-bootstrap.conf ]]; then
    printf "  ${GREEN}+${NC} %-26s applied (/etc/sysctl.d/99-bootstrap.conf)\n" "sysctl hardening"
fi

if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    printf "  ${GREEN}+${NC} %-26s configured\n" "unattended-upgrades"
fi

echo ""
echo "  Ansible venv:   /opt/bootstrap-venv/"
echo "  Playbooks:      $BOOTSTRAP_DIR"
echo "  Re-run:         cd $BOOTSTRAP_DIR && source /opt/bootstrap-venv/bin/activate && ansible-playbook -i inventory/local.yml $PLAYBOOK$EXTRA_ARGS"
echo "  Full log:       $LOG_FILE"
echo ""

if [[ $ANSIBLE_EXIT -eq 0 ]]; then
    banner "Setup Complete"
    ok "All tasks succeeded. System configured with role: $ROLE"
else
    banner "Setup Finished (with errors)"
    err "Playbook exited with code: $ANSIBLE_EXIT"
    warn "Some tasks may have failed. See full log: cat $LOG_FILE"
    exit $ANSIBLE_EXIT
fi

