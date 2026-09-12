# Set up restic backups to a remote host reachable over SSH. The repository,
# passphrase, and a dedicated root SSH key are stored under /etc/restic and
# /root/.ssh (root-only; never part of the image). Run this once after rebase
# (or from the repo with: just -f files/justfiles/restic.just restic-setup).
#
# The canonical exclude list lives in 'restic-sync-excludes' below and must
# match files/system/etc/restic/excludes (shipped in the image). It is
# refreshed on every setup and backup run, so image updates to the list apply
# to existing machines. Each backup also runs 'restic forget --prune' with the
# retention policy documented on 'restic-backup'.
restic-setup: restic-sync-excludes
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

    # Excludes were already refreshed by the restic-sync-excludes dependency.
    # Dedicated SSH key for root-run restic access to the backup host.
    # /root/.ssh is root-only (0700), so existence must be checked via sudo.
    sudo install -d -m 0700 /root/.ssh
    if ! sudo test -f /root/.ssh/id_ed25519; then
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

# Refresh /etc/restic/excludes from the canonical list baked into this recipe.
# This is the single source of truth at runtime: it must match
# files/system/etc/restic/excludes (the copy shipped in the image for fresh
# installs). Shipping a file in the image alone does not update existing
# machines, so restic-setup and restic-backup both run this first.
restic-sync-excludes:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo install -d -m 0700 /etc/restic
    cat <<'EOF' | sudo tee /etc/restic/excludes >/dev/null
    /var/lib/flatpak
    /var/lib/containers/storage
    /var/lib/ollama/models
    /var/lib/nathanw/models
    /var/home/*/.cache
    /var/home/*/.local/share/Trash
    /var/home/*/.npm
    /var/home/*/.rustup
    /var/home/*/.cargo/registry
    /var/home/*/.local/share/Steam/steamapps/shadercache
    EOF
    sudo chown root:root /etc/restic/excludes
    sudo chmod 0600 /etc/restic/excludes
    echo "Refreshed /etc/restic/excludes."

# Run a restic backup of /etc, /var/lib and the invoking user's home directory,
# using the root-only configuration created by 'restic-setup'. The exclude
# list is refreshed first (see restic-sync-excludes), then a backup runs,
# followed by 'forget --prune' with the retention below.
#
# Retention: keep 7 daily, 4 weekly, 6 monthly snapshots. Old snapshots beyond
# that are forgotten and their unreferenced data pruned on every backup run,
# so repository growth is bounded. Run 'ujust restic-forget' to apply the
# policy without taking a new snapshot.
restic-backup: restic-sync-excludes
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "Run 'ujust restic-backup' as your desktop user, not as root." >&2
        exit 1
    fi
    # /etc/restic is root-only (0700), so existence must be checked via sudo.
    if ! sudo test -f /etc/restic/env; then
        echo "No restic configuration found. Run 'ujust restic-setup' first." >&2
        exit 1
    fi

    echo "Starting restic backup of /etc, /var/lib and /var/home/${USER}..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic backup \
        /etc /var/lib "/var/home/${SUDO_USER}" \
        --exclude-file=/etc/restic/excludes --exclude-if-present=.nobackup'
    echo "Applying retention (forget --prune: 7 daily, 4 weekly, 6 monthly)..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic forget --prune \
        --keep-daily 7 --keep-weekly 4 --keep-monthly 6'
    echo "Backup complete. See 'ujust restic-snapshots' for stored snapshots."

# Apply the retention policy without taking a new snapshot.
# Useful after exclude-list changes: snapshots taken before a path was
# excluded still reference its blobs, so space is only reclaimed once those
# snapshots are forgotten and prune runs. For immediate reclaim, forget the
# pre-exclude snapshot IDs explicitly, e.g.:
# sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic forget <id>... --prune'
restic-forget:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! sudo test -f /etc/restic/env; then
        echo "No restic configuration found. Run 'ujust restic-setup' first." >&2
        exit 1
    fi
    echo "Forgetting snapshots beyond retention (7 daily, 4 weekly, 6 monthly)..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic forget --prune \
        --keep-daily 7 --keep-weekly 4 --keep-monthly 6'

# List restic snapshots stored on the backup host.
restic-snapshots:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! sudo test -f /etc/restic/env; then
        echo "No restic configuration found. Run 'ujust restic-setup' first." >&2
        exit 1
    fi
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic snapshots'

# Verify repository integrity (read-only check of structure and data).
restic-check:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! sudo test -f /etc/restic/env; then
        echo "No restic configuration found. Run 'ujust restic-setup' first." >&2
        exit 1
    fi
    echo "Checking repository integrity (this can take a while)..."
    sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic check'
