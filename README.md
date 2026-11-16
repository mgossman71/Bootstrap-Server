# Bootstrap Server

A Docker container that hosts Ansible playbooks and bootstrap scripts for automated setup of Ubuntu 24.04 VMs and LXC containers.

## Quick Start

### 1. Configure

```bash
cp .env.example .env
```

Edit `.env` and set `BOOTSTRAP_PUBLIC_URL` to the LAN IP your VMs will use:

```bash
BOOTSTRAP_PUBLIC_URL=http://192.168.1.50:9090
```

Find your IP: `ip get | grep inet` (macOS) or `hostname -I` (Linux)

### 2. Start the server

```bash
docker compose up -d --build
```

### 3. Use from a new VM/LXC

Open **http://\<server-ip\>:9090** in a browser from any machine — the dashboard shows copy/paste commands with the correct LAN IP baked in.

Or manually from a fresh Ubuntu 24.04 VM terminal:

```bash
curl -fsSL http://<server-ip>:9090/bootstrap.sh | sudo bash -s -- --server http://<server-ip>:9090 --role vm
```

### Development (live reload)

The `docker-compose.yml` bind-mounts `./serve` into the container. Edit files in `serve/` and refresh — no rebuild needed.

## Available Roles

| Role | Description |
|------|-------------|
| `vm` | Full VM setup (updates, security, network, docker) |
| `lxc-host` | LXC host prep (bridge networking, cgroups, tooling) |
| `lxc-container` | Minimal container setup |
| `security` | Security hardening only (SSH, fail2ban; firewall left off) |
| `docker` | Docker CE install only |
| `minimal` | Base packages only |

## Configuration

- **Server IP for commands**: Set `BOOTSTRAP_PUBLIC_URL` in `.env` (critical — see above)
- **Packages/timezone/etc.**: Edit `serve/roles/common/defaults/main.yml`
- **Firewall**: Off by default. Set `ufw_enable: true` in `serve/roles/security/defaults/main.yml` to deny incoming except SSH
- **SSH rules**: Root login and password login are on by default (`ssh_permit_root_login`, `ssh_password_auth`). Edit `serve/roles/security/defaults/main.yml` and the drop-in task in `serve/roles/security/tasks/main.yml` (written to `/etc/ssh/sshd_config.d/00-bootstrap.conf`)
- **All playbooks are idempotent** — safe to run multiple times

## Project Structure

```
├── Dockerfile              # Alpine + Nginx
├── docker-entrypoint.sh    # Injects BOOTSTRAP_PUBLIC_URL at startup
├── docker-compose.yml      # Port 9090, volume mount, env config
├── .env.example            # Copy to .env, set your LAN IP
├── nginx/default.conf      # Nginx routing + API endpoints
├── serve/                  # Everything served to VMs
│   ├── index.html          # Dashboard with copy/paste commands
│   ├── bootstrap.sh        # Entry-point script for new VMs
│   ├── playbooks/          # Ansible playbooks
│   ├── roles/              # Ansible roles
│   ├── inventory/          # Ansible inventory
│   └── ansible.cfg         # Ansible configuration
├── scripts/build.sh        # Local build helper
└── .github/workflows/      # CI: build, push, smoke test
```

## GitHub Integration

- PRs to `main` trigger a build & push to GHCR via GitHub Actions
- On the host: `docker compose pull && docker compose up -d` updates the server
- Git SHA is injected into the container and displayed on the dashboard
