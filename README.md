\# linux-server-automation



Automated Linux server deployment script for ITMO 453/553.



\## What it does



\- Updates the system and installs required packages

\- Creates a non-root admin user with SSH key authentication

\- Hardens SSH and disables password login

\- Configures UFW firewall and fail2ban

\- Deploys NGINX with a landing page

\- Sets up logging and automated health checks



\## Requirements



\- Ubuntu Server LTS

\- Run as root

\- Internet connection

\- SSH public key ready to paste



\## Usage



```bash

sudo bash deploy.sh

```



When prompted, paste your SSH public key.



\## Configuration



Edit the variables at the top of deploy.sh to customize:



| Variable     | Default             |

|--------------|---------------------|

| ADMIN\_USER   | adminuser           |

| HOSTNAME     | lab-server          |

| SSH\_PORT     | 22                  |

| HTTP\_PORT    | 80                  |

| HTTPS\_PORT   | 443                 |



\## Utility Scripts



After deployment these commands are available on the server:



| Command          | What it does                           |

|------------------|----------------------------------------|

| health-check     | Verifies all services are running      |

| log-summary      | Shows logins, failures, disk/memory    |

| metrics-snapshot | CPU, memory, disk, and network stats   |

