# Set up restic backups to a remote host reachable over SSH. The repository,
# passphrase, and a dedicated root SSH key are stored under /etc/restic and
# /root/.ssh (root-only; never part of the image). Run this once after rebase
# (or from the repo with: just -f files/justfiles/restic.just restic-setup).
restic-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "Run 'ujust restic-setup' as your desktop user, not as root." >&2
        exit 1
    fi

    echo "restic backup setup"
    echo "-------------------"
    echo "This configures root-run restic backups of /etc, /var/lib and your"
    echo "home directory to a remote host over SSH (sftp backend). It writes"
    echo "root-only state under /etc/restic and /root/.ssh and authorizes the"
    echo "dedicated backup key on the remote account."
    echo

    read -r -p "Backup host (user@host) [eirik@bokhylla]: " REMOTE
    REMOTE="${REMOTE:-eirik@bokhylla}"
    read -r -p "Repository directory on ${REMOTE} [/tank/pc/bazzite/restic]: " REPO_DIR
    REPO_DIR="${REPO_DIR:-/tank/pc/bazzite/restic}"

    # The remote directory must be creatable with the remote account (e.g. a
    # ZFS dataset owned by that user). Validate before touching local state.
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE}" \
        "umask 077; mkdir -p '${REPO_DIR}' && touch '${REPO_DIR}/.write-test' && rm '${REPO_DIR}/.write-test'"; then
        echo "Could not create or write to ${REPO_DIR} on ${REMOTE}." >&2
        echo "On bokhylla, for example, create a dataset owned by the backup user:" >&2
        echo "  ssh bokhylla 'sudo zfs create tank/pc/bazzite && sudo chown eirik:users /tank/pc/bazzite'" >&2
        exit 1
    fi

    # Repository passphrase. /etc/restic is root-only, matching the root-run
    # backups; keep a copy of this passphrase in your password manager.
    PASS="$(openssl rand -hex 16)"

    sudo install -d -m 0700 /etc/restic
    printf 'RESTIC_REPOSITORY=sftp:%s:%s\nRESTIC_PASSWORD_FILE=/etc/restic/password\n' \
        "${REMOTE}" "${REPO_DIR}" | sudo tee /etc/restic/env >/dev/null
    printf '%s\n' "${PASS}" | sudo tee /etc/restic/password >/dev/null
    sudo chown root:root /etc/restic/env /etc/restic/password
    sudo chmod 0600 /etc/restic/env /etc/restic/password

    # Canonical exclude list (also shipped in the image at /etc/restic/excludes).
    if [[ ! -f /etc/restic/excludes ]]; then
        printf '%s\n' \
            '/var/lib/flatpak' \
            '/var/lib/containers/storage' \
            '/var/lib/ollama/models' \
            '/var/home/*/.cache' \
            '/var/home/*/.local/share/Trash' \
            '/var/home/*/.npm' \
            '/var/home/*/.rustup' \
            '/var/home/*/.cargo/registry' \
            '/var/home/*/.local/share/Steam/steamapps/shadercache' \
            | sudo tee /etc/restic/excludes >/dev/null
        sudo chown root:root /etc/restic/excludes
        sudo chmod 0600 /etc/restic/excludes
    fi

    # Dedicated SSH key for root-run restic access to the backup host.
    sudo install -d -m 0700 /root/.ssh
    if [[ ! -f /root/.ssh/id_ed25519 ]]; then
        sudo ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519 -C "restic-backup@$(hostname)"
    fi
    BACKUP_KEY="$(sudo cat /root/.ssh/id_ed25519.pub)"

    # Authorize the root backup key on the remote account by appending it over
    # the desktop user's existing SSH access.
    if ! ssh -o BatchMode=yes "${REMOTE}" "grep -qxF '${BACKUP_KEY}' ~/.ssh/authorized_keys 2>/dev/null"; then
        ssh "${REMOTE}" "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; echo '${BACKUP_KEY}' >> ~/.ssh/authorized_keys"
        echo "Authorized the root backup key on ${REMOTE}."
    else
        echo "Root backup key already authorized on ${REMOTE}."
    fi

    # Trust the remote host key for root and initialize the repository.
    sudo ssh -o StrictHostKeyChecking=accept-new "${REMOTE}" true
    echo "Initializing restic repository..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; restic init'
    echo "Verifying repository access..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; restic snapshots'

    echo
    echo "Done. Backup passphrase (store it somewhere safe):"
    echo "  ${PASS}"
    echo "Run your first backup with 'ujust restic-backup' (or"
    echo "'just -f files/justfiles/restic.just restic-backup' before the next rebase)."

# Run a restic backup of /etc, /var/lib and the invoking user's home directory,
# using the root-only configuration created by 'restic-setup'.
restic-backup:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "Run 'ujust restic-backup' as your desktop user, not as root." >&2
        exit 1
    fi
    if [[ ! -f /etc/restic/env ]]; then
        echo "No restic configuration found. Run 'ujust restic-setup' first." >&2
        exit 1
    fi

    echo "Starting restic backup of /etc, /var/lib and /var/home/${SUDO_USER}..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic backup \
        /etc /var/lib "/var/home/${SUDO_USER}" \
        --exclude-file=/etc/restic/excludes --exclude-if-present=.nobackup'
    echo "Backup complete. See 'ujust restic-snapshots' for stored snapshots."

# List restic snapshots stored on the backup host.
restic-snapshots:
    #!/usr/bin/env bash
    set -euo pipefail

    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic snapshots'

# Verify repository integrity (read-only check of structure and data).
restic-check:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Checking repository integrity (this can take a while)..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic check'
