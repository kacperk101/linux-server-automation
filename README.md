# linux-server-automation

Automated Linux server deployment for ITMO 453/553.
Combines a Bash deployment script and Ansible playbooks to provision and harden a fresh Ubuntu Server LTS instance.

## What it does

- Updates the system and installs required packages
- Creates a non-root admin user with SSH key authentication
- Hardens SSH and disables password login
- Configures UFW firewall and fail2ban
- Deploys NGINX with a landing page
- Installs Docker and deploys a container
- Sets up logging and automated health checks
- Schedules automated backups and system updates

## Repository Structure


## Requirements

- Ubuntu Server LTS
- Internet connection
- SSH public key ready to paste

## Option 1 — Bash Script

Run on the target server directly as root:

```bash
sudo bash deploy.sh
```

When prompted, paste your SSH public key.

## Option 2 — Ansible (recommended)

Run from a control machine (Linux or WSL) targeting the server remotely.

### Prerequisites

```bash
sudo apt install -y ansible
```

### Setup

1. Update `ansible/inventory.ini` with your server's IP:

```ini
[linux_server]
your.server.ip

[linux_server:vars]
ansible_user = your_username
ansible_ssh_private_key_file = ~/.ssh/id_ed25519
ansible_python_interpreter = /usr/bin/python3
```

2. Update `ansible/group_vars/linux_server.yml` with your details:

```yaml
admin_user: your_username
student_name: Your Name
ssh_public_key: "ssh-ed25519 AAAA... your-key"
```

3. Test the connection:

```bash
cd ansible
ansible linux_server -m ping
```

4. Run the full deployment:

```bash
ansible-playbook site.yml
```

Or run individual playbooks:

```bash
ansible-playbook playbooks/01-system.yml
ansible-playbook playbooks/02-security.yml
ansible-playbook playbooks/03-webserver.yml
ansible-playbook playbooks/04-docker.yml
ansible-playbook playbooks/05-maintenance.yml
```

## Configuration

Edit variables at the top of `deploy.sh` or in `ansible/group_vars/linux_server.yml`:

| Variable | Default | Description |
|---|---|---|
| ADMIN_USER / admin_user | adminuser | Non-root admin username |
| HOSTNAME | lab-server | Server hostname |
| SSH_PORT | 22 | SSH port |
| HTTP_PORT | 80 | HTTP port |
| HTTPS_PORT | 443 | HTTPS port |

## Utility Scripts

After deployment, these commands are available on the server:

| Command | What it does |
|---|---|
| health-check | Verifies all services and ports are running |
| log-summary | Shows SSH logins, failures, disk and memory |
| metrics-snapshot | CPU, memory, disk, and network stats |
