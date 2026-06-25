\# Architecture Overview



\## What gets deployed



A single Bash script provisions a fresh Ubuntu Server LTS instance from scratch.

Running it once produces a fully configured and hardened server with no manual steps.



\## Components



\*\*OS:\*\* Ubuntu Server LTS on VMware Workstation with automatic security updates.



\*\*Access:\*\* Non-root admin user with sudo access. SSH key authentication only —

passwords and root login are disabled.



\*\*Firewall:\*\* UFW set to deny all inbound traffic by default. Only ports 22, 80,

and 443 are open. SSH is rate-limited. fail2ban bans IPs after 3 failed attempts.



\*\*Web:\*\* NGINX on port 80 with basic security headers and a landing page.

Starts automatically on boot.



\*\*Logging:\*\* journald stores logs persistently for 30 days. NGINX logs rotate

daily. A log summary runs every morning at 06:00 via cron.



\*\*Monitoring:\*\* A health check script runs every 5 minutes and verifies all

services, ports, and HTTP response. A metrics snapshot runs hourly capturing

CPU, memory, disk, and network stats.



\## Script flow



1\. Pre-flight checks

2\. System update and package install

3\. Admin user creation

4\. SSH key setup

5\. SSH hardening

6\. Firewall configuration

7\. NGINX deployment

8\. Logging setup

9\. Monitoring setup



\## Security principles



\- Least privilege — non-root user, minimal open ports

\- Defense in depth — UFW, fail2ban, and SSH hardening layered together

\- Deny by default — explicit allowlist rather than blocklist

\- Auditability — persistent logs, daily summaries, automated health checks

