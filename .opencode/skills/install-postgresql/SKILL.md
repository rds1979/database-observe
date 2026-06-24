---
name: install-postgresql
description: Use to install PostgreSQL on a remote host via SSH. Connects to 10.92.94.41 using src/ssh/config, installs PostgreSQL (latest version available in the distro repos), verifies the installation, and starts the service. Run only when explicitly asked.
---

# Install PostgreSQL on remote host

## Connection

- SSH config: `src/ssh/config`
- Host alias: `10.92.94.41`
- Connect via: `ssh -F src/ssh/config 10.92.94.41`
- All commands must be run **on the remote host** through SSH.

## OS detection

Before installing, detect the OS:

```bash
. /etc/os-release && echo "$ID $VERSION_ID"
```

Supported families:
- `ubuntu` / `debian` — use `apt`
- `rhel` / `centos` / `rocky` / `almalinux` — use `dnf` (or `yum` on older)
- `fedora` — use `dnf`
- `sles` / `opensuse` — use `zypper`

If the OS is not in this list, abort with an error.

## Installation procedure

### 1. Add official PostgreSQL repository (recommended)

For **apt-based** (Ubuntu/Debian):

```bash
apt update && apt install -y curl ca-certificates
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
sh -c 'echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
apt update && apt install -y postgresql
```

For **dnf-based** (RHEL/CentOS/Rocky/Alma/Fedora):

```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-$(rpm -E %{rhel})-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql
dnf install -y postgresql-server postgresql-contrib
```

For **zypper-based** (SLES/openSUSE):

```bash
zypper addrepo https://download.postgresql.org/pub/repos/zypp/$(. /etc/os-release; echo "$VERSION_ID")/repo-suse/repo-suse-pgdg.repo
zypper refresh && zypper install -y postgresql-server postgresql-contrib
```

### 2. Initialize and start

```bash
# Check if already initialized
if [ ! -d /var/lib/pgsql/data ] && [ ! -d /var/lib/postgresql/*/main ]; then
  # RHEL-based
  [ -f /usr/bin/postgresql-setup ] && postgresql-setup --initdb
  # Debian-based — package does this automatically
fi

systemctl enable postgresql
systemctl start postgresql
```

### 3. Verify installation

```bash
psql --version
systemctl status postgresql --no-pager
sudo -u postgres psql -c "SELECT version();"
```

All three commands must succeed. If any fails, abort and report the error.

## Firewall

If `firewalld` or `ufw` is active, open port 5432:

- **firewalld**: `firewall-cmd --add-service=postgresql --permanent && firewall-cmd --reload`
- **ufw**: `ufw allow postgresql`

Do this only if the user explicitly asks for remote access.

## Error handling

- If SSH connection fails, abort — do not retry.
- If OS is unsupported, abort with a clear message.
- If any installation command fails, log the error and abort.
- If `systemctl` fails, try `service postgresql start` as a fallback.
- Log every major step (OS detected, repo added, package installed, service started).

## Limitations

- Installs the latest PostgreSQL available in the official PGDG repo for the detected OS.
- Does **not** configure `pg_hba.conf`, `postgresql.conf`, or tuning parameters.
- Does **not** set up replication, backups, or extensions (those are separate skills).
