#!/bin/bash

set -euo pipefail

#CONFIGURATION

ADMIN_USER="adminuser"
HOSTNAME="lab-server"
SSH_PORT="22"
HTTP_PORT="80"
HTTPS_PORT="443"
LOG_FILE="/var/log/deploy.log"
NGINX_ROOT="/var/www/html"
STUDENT_NAME="Kacper Kraj"
COURSE="ITMO 453/553"

#Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#HELPERS

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"; echo "[$(date '+%H:%M:%S')] WARNING: $1" >> "$LOG_FILE"; }
error(){ echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"; echo "[$(date '+%H:%M:%S')] ERROR: $1" >> "$LOG_FILE"; exit 1; }

#PRE-CHECKS

check_root() {
    [[ "${EUID}" -ne 0 ]] && error "Run this script as root: sudo bash deploy.sh"
    log "Running as root."
}

check_ubuntu() {
    grep -qi "ubuntu" /etc/os-release || error "This script requires Ubuntu Server."
    log "Ubuntu detected."
}

check_internet() {
    ping -c 1 google.com &>/dev/null || error "No internet connection."
    log "Internet connection confirmed."
}

#SYSTEM UPDATE AND PACKAGES

phase_system_update() {
    log "--- Phase 1: System Update & Packages ---"
    export DEBIAN_FRONTEND=noninteractive

    log "Updating package list..."
    apt-get update -qq || error "apt-get update failed."

    log "Upgrading packages..."
    apt-get upgrade -y -qq || error "apt-get upgrade failed."

    log "Installing required packages..."
    local packages=(curl wget vim ufw nginx fail2ban unattended-upgrades git htop net-tools)

    for pkg in "${packages[@]}"; do
        if dpkg -l "$pkg" &>/dev/null; then
            warn "$pkg already installed — skipping."
        else
            log "Installing $pkg..."
            apt-get install -y -qq "$pkg" || error "Failed to install $pkg."
        fi
    done

    log "Enabling automatic security updates..."
    dpkg-reconfigure -plow unattended-upgrades || warn "Could not configure unattended-upgrades."

    log "Phase 1 complete."
}

#USER CREATION

phase_create_user() {
    log "--- Phase 2: User Creation ---"

    if id "$ADMIN_USER" &>/dev/null; then
        warn "User $ADMIN_USER already exists — skipping."
    else
        useradd -m -s /bin/bash "$ADMIN_USER" || error "Failed to create user."
        usermod -aG sudo "$ADMIN_USER" || error "Failed to add user to sudo group."
        log "User $ADMIN_USER created and added to sudo group."
    fi

    local ssh_dir="/home/${ADMIN_USER}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "${ADMIN_USER}:${ADMIN_USER}" "$ssh_dir"
        log ".ssh directory created."
    else
        warn ".ssh directory already exists — skipping."
    fi

    if [[ ! -f "$auth_keys" ]]; then
        touch "$auth_keys"
        chmod 600 "$auth_keys"
        chown "${ADMIN_USER}:${ADMIN_USER}" "$auth_keys"
        log "authorized_keys created."
    else
        warn "authorized_keys already exists — skipping."
    fi

    log "Phase 2 complete."
}

#SSH KEY SETUP

phase_setup_ssh_key() {
    log "--- Phase 3: SSH Key Setup ---"

    local auth_keys="/home/${ADMIN_USER}/.ssh/authorized_keys"

    if [[ -s "$auth_keys" ]]; then
        warn "SSH key already present — skipping."
        return 0
    fi

    echo ""
    echo -e "${YELLOW}=========================================="
    echo "  SSH PUBLIC KEY SETUP"
    echo "  Paste your public key (starts with ssh-ed25519 or ssh-rsa)"
    echo -e "==========================================${NC}"
    read -rp "Paste public key: " PUBLIC_KEY

    [[ -z "$PUBLIC_KEY" ]] && error "No key provided."
    [[ "$PUBLIC_KEY" != ssh-* ]] && error "Invalid key format — must start with ssh-ed25519 or ssh-rsa."

    echo "$PUBLIC_KEY" > "$auth_keys"
    chmod 600 "$auth_keys"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$auth_keys"

    grep -q "$PUBLIC_KEY" "$auth_keys" || error "Key verification failed."
    log "SSH public key written and verified."

    log "Phase 3 complete."
}

#SSH HARDENING

phase_harden_ssh() {
    log "--- Phase 4: SSH Hardening ---"

    local sshd_config="/etc/ssh/sshd_config"

    #Backup config
    if [[ ! -f "${sshd_config}.bak" ]]; then
        cp "$sshd_config" "${sshd_config}.bak"
        log "sshd_config backed up."
    else
        warn "Backup already exists — skipping."
    fi

    #Apply settings
    declare -A settings=(
        ["PermitRootLogin"]="no"
        ["PasswordAuthentication"]="no"
        ["PubkeyAuthentication"]="yes"
        ["PermitEmptyPasswords"]="no"
        ["X11Forwarding"]="no"
        ["MaxAuthTries"]="3"
        ["LoginGraceTime"]="20"
        ["Port"]="$SSH_PORT"
    )

    for key in "${!settings[@]}"; do
        val="${settings[$key]}"
        if grep -q "^${key}" "$sshd_config"; then
            sed -i "s/^${key}.*/${key} ${val}/" "$sshd_config"
        elif grep -q "^#${key}" "$sshd_config"; then
            sed -i "s/^#${key}.*/${key} ${val}/" "$sshd_config"
        else
            echo "${key} ${val}" >> "$sshd_config"
        fi
        log "Set: $key $val"
    done

    sshd -t || error "SSH config validation failed."
    systemctl restart ssh || error "Failed to restart SSH."
    systemctl enable ssh
    log "Phase 4 complete."
}

#FIREWALL

phase_configure_firewall() {
    log "--- Phase 5: Firewall Configuration ---"

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit "${SSH_PORT}"/tcp
    ufw allow "${HTTP_PORT}"/tcp
    ufw allow "${HTTPS_PORT}"/tcp
    ufw --force enable

    ufw status | grep -q "Status: active" || error "UFW failed to activate."
    log "UFW enabled with rules: SSH (rate-limited), HTTP, HTTPS."

    # Configure fail2ban
    if [[ ! -f /etc/fail2ban/jail.local ]]; then
        cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 7200
EOF
        log "fail2ban configured."
    else
        warn "fail2ban jail.local already exists — skipping."
    fi

    systemctl enable fail2ban
    systemctl restart fail2ban
    systemctl is-active --quiet fail2ban || error "fail2ban failed to start."
    log "fail2ban active."

    log "Phase 5 complete."
}

#NGINX

phase_deploy_nginx() {
    log "--- Phase 6: NGINX Deployment ---"

    command -v nginx &>/dev/null || error "NGINX not installed."

    #Backup default config
    if [[ ! -f /etc/nginx/sites-available/default.bak ]]; then
        cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
        log "NGINX default config backed up."
    else
        warn "NGINX backup already exists — skipping."
    fi

    # Write server block
    cat > /etc/nginx/sites-available/default << NGINXCONF
server {
    listen ${HTTP_PORT} default_server;
    listen [::]:${HTTP_PORT} default_server;

    root ${NGINX_ROOT};
    index index.html;
    server_name _;
    server_tokens off;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\. {
        deny all;
    }
}
NGINXCONF

    # Deploy landing page
    cat > "${NGINX_ROOT}/index.html" << HTMLPAGE
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Lab Server — ${STUDENT_NAME}</title>
    <style>
        body { font-family: sans-serif; max-width: 600px; margin: 60px auto; padding: 0 20px; color: #333; }
        h1 { color: #c00; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        td, th { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
        th { background: #f4f4f4; }
    </style>
</head>
<body>
    <h1>Lab Server — ${STUDENT_NAME}</h1>
    <table>
        <tr><th>Field</th><th>Value</th></tr>
        <tr><td>Student</td><td>${STUDENT_NAME}</td></tr>
        <tr><td>Course</td><td>${COURSE}</td></tr>
        <tr><td>Hostname</td><td>${HOSTNAME}</td></tr>
        <tr><td>OS</td><td>Ubuntu Server LTS</td></tr>
        <tr><td>Web Server</td><td>NGINX</td></tr>
        <tr><td>Deployed</td><td>$(date '+%Y-%m-%d %H:%M:%S')</td></tr>
    </table>
</body>
</html>
HTMLPAGE

    chown -R www-data:www-data "$NGINX_ROOT"
    chmod -R 755 "$NGINX_ROOT"

    nginx -t || error "NGINX config validation failed."
    systemctl enable nginx
    systemctl restart nginx
    systemctl is-active --quiet nginx || error "NGINX failed to start."

    curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200" \
        && log "Landing page returned HTTP 200 — OK." \
        || warn "Landing page check failed. Check /var/log/nginx/error.log."

    log "Phase 6 complete."
}

#LOGGING

phase_setup_logging() {
    log "--- Phase 7: Logging Setup ---"

    # Persistent journald
    if [[ ! -f /etc/systemd/journald.conf.bak ]]; then
        cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak
    fi

    cat > /etc/systemd/journald.conf << EOF
[Journal]
Storage=persistent
SystemMaxUse=500M
MaxRetentionSec=30day
Compress=yes
EOF
    systemctl restart systemd-journald
    log "journald configured for persistent logging."

    # NGINX log rotation
    cat > /etc/logrotate.d/nginx-custom << EOF
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    sharedscripts
    postrotate
        nginx -s reopen
    endscript
}
EOF
    log "NGINX log rotation configured."

    # Daily log summary script
    cat > /usr/local/bin/log-summary << 'EOF'
#!/bin/bash
echo "=============================="
echo " Log Summary — $(date)"
echo "=============================="
echo ""
echo "--- Successful SSH logins (last 24h) ---"
journalctl -u ssh --since "24 hours ago" | grep "Accepted" | tail -10
echo ""
echo "--- Failed SSH attempts (last 24h) ---"
journalctl -u ssh --since "24 hours ago" | grep "Failed" | wc -l
echo ""
echo "--- Banned IPs (fail2ban) ---"
fail2ban-client status sshd 2>/dev/null | grep "Banned IP"
echo ""
echo "--- Disk usage ---"
df -h /
echo ""
echo "--- Memory usage ---"
free -h
EOF
    chmod +x /usr/local/bin/log-summary

    #Schedule daily at 6am
    echo "0 6 * * * root /usr/local/bin/log-summary >> /var/log/daily-summary.log 2>&1" \
        > /etc/cron.d/log-summary
    log "Daily log summary scheduled at 06:00."

    log "Phase 7 complete."
}

#MONITORING

phase_setup_monitoring() {
    log "--- Phase 8: Monitoring Setup ---"

    #Health check script
    cat > /usr/local/bin/health-check << 'EOF'
#!/bin/bash
PASS=0
FAIL=0

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo "[OK]   $1 is running"
        ((PASS++))
    else
        echo "[FAIL] $1 is NOT running"
        ((FAIL++))
    fi
}

check_port() {
    if ss -tulnp | grep -q ":$1"; then
        echo "[OK]   Port $1 ($2) is listening"
        ((PASS++))
    else
        echo "[FAIL] Port $1 ($2) is NOT listening"
        ((FAIL++))
    fi
}

echo "=============================="
echo " Health Check — $(date)"
echo "=============================="
echo ""
echo "--- Services ---"
check_service ssh
check_service nginx
check_service ufw
check_service fail2ban

echo ""
echo "--- Ports ---"
check_port 22 "SSH"
check_port 80 "HTTP"

echo ""
echo "--- Web ---"
code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
[[ "$code" == "200" ]] && echo "[OK]   HTTP 200 from localhost" || echo "[FAIL] Got HTTP $code from localhost"

echo ""
echo "--- Firewall ---"
ufw status | grep -q "Status: active" \
    && echo "[OK]   UFW is active" \
    || echo "[FAIL] UFW is inactive"

echo ""
echo "=============================="
echo " Results: $PASS passed, $FAIL failed"
echo "=============================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
EOF
    chmod +x /usr/local/bin/health-check
    log "Health check script created."

    # Metrics snapshot script
    cat > /usr/local/bin/metrics-snapshot << 'EOF'
#!/bin/bash
echo "=============================="
echo " Metrics Snapshot — $(date)"
echo "=============================="
echo "--- CPU ---"
top -bn1 | grep "Cpu(s)"
echo "--- Memory ---"
free -h
echo "--- Disk ---"
df -h /
echo "--- Listening ports ---"
ss -tulnp
echo "--- Top processes ---"
ps aux --sort=-%cpu | head -6
EOF
    chmod +x /usr/local/bin/metrics-snapshot
    log "Metrics snapshot script created."

    #Schedule health check every 5 minutes
    echo "*/5 * * * * root /usr/local/bin/health-check >> /var/log/health-check.log 2>&1" \
        > /etc/cron.d/health-check

    #Schedule metrics snapshot hourly
    echo "0 * * * * root /usr/local/bin/metrics-snapshot >> /var/log/metrics.log 2>&1" \
        > /etc/cron.d/metrics-snapshot

    log "Health check scheduled every 5 minutes."
    log "Metrics snapshot scheduled hourly."

    #Run health check immediately
    log "Running initial health check..."
    /usr/local/bin/health-check >> "$LOG_FILE" 2>&1 \
        && log "Initial health check passed." \
        || warn "Initial health check reported failures — review $LOG_FILE."

    log "Phase 8 complete."
}

#MAIN

main() {
    log "=========================================="
    log " Automated Server Deployment"
    log " Student: ${STUDENT_NAME} | ${COURSE}"
    log "=========================================="

    check_root
    check_ubuntu
    check_internet

    phase_system_update
    phase_create_user
    phase_setup_ssh_key
    phase_harden_ssh
    phase_configure_firewall
    phase_deploy_nginx
    phase_setup_logging
    phase_setup_monitoring

    log "=========================================="
    log " Deployment complete."
    log " Run 'health-check' to verify services."
    log " Run 'log-summary' for a log overview."
    log " Run 'metrics-snapshot' for system stats."
    log " Full log: ${LOG_FILE}"
    log "=========================================="
}

main "$@"