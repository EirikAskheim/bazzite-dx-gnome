# n8n workflow automation (baked into the image by recipes/recipe.yml).
# The service runs as the `n8n` system user with state in /var/lib/n8n and
# is enabled by default. This recipe generates the encryption key on first
# use, applies host-specific overrides (port, host, auth), and starts the
# service. See README.md ("n8n") for the full picture.
#
# Env overrides: N8N_PORT, N8N_HOST, N8N_BASIC_AUTH_USER, N8N_BASIC_AUTH_PASSWORD.
#
# Note on `ujust --list`: just uses the LAST line of the comment block above a
# recipe as its description, so the summary goes last in these blocks.

# Generate the encryption key (once), apply config, enable + start n8n.
n8n-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -x /usr/bin/n8n ]; then
        echo "n8n is not installed at /usr/bin/n8n — rebase to an image containing it first." >&2
        exit 1
    fi

    CONF="/etc/n8n/n8n.conf"
    STATE_DIR="/var/lib/n8n"
    N8N_DIR="${STATE_DIR}/.n8n"

    sudo install -d -m 0750 -o n8n -g n8n "${STATE_DIR}" "${N8N_DIR}"
    sudo install -d -m 0755 /etc/n8n

    # n8n encrypts credentials with N8N_ENCRYPTION_KEY. Generate one locally
    # (root-only, never part of the image) if neither the conf nor the
    # environment provides it. Existing installs keep their key.
    CONFIG_KEY=""
    if [ -f "${CONF}" ]; then
        CONFIG_KEY="$(sudo grep -h '^N8N_ENCRYPTION_KEY=' "${CONF}" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
    fi
    NEW_KEY=""
    if [ -z "${CONFIG_KEY:-}" ] && [ -z "${N8N_ENCRYPTION_KEY:-}" ]; then
        NEW_KEY="$(openssl rand -hex 32)"
        printf 'N8N_ENCRYPTION_KEY=%s\n' "${NEW_KEY}" | sudo tee -a "${CONF}" >/dev/null
        sudo chmod 0600 "${CONF}"
        echo "Generated a new encryption key in ${CONF} (root-only). Back it up — losing it locks you out of stored credentials."
    fi

    # Host defaults live in the unit; only write host-specific overrides
    # given as environment variables so image updates to the defaults apply.
    # The `|| true` guards keep `set -o pipefail` from aborting when grep
    # finds no match or the conf is absent.
    write_key() {
        local key="$1" value="$2"
        sudo touch "${CONF}"
        sudo chmod 0600 "${CONF}"
        if sudo grep -q "^${key}=" "${CONF}" 2>/dev/null; then
            sudo sed -i "s|^${key}=.*|${key}=${value}|" "${CONF}"
        else
            printf '%s=%s\n' "${key}" "${value}" | sudo tee -a "${CONF}" >/dev/null
        fi
    }
    if [ -n "${N8N_ENCRYPTION_KEY:-}" ] && [ "${N8N_ENCRYPTION_KEY}" != "${CONFIG_KEY:-}" ]; then
        write_key "N8N_ENCRYPTION_KEY" "${N8N_ENCRYPTION_KEY}"
    fi
    if [ -n "${N8N_PORT:-}" ]; then
        write_key "N8N_PORT" "${N8N_PORT}"
    fi
    if [ -n "${N8N_HOST:-}" ]; then
        write_key "N8N_HOST" "${N8N_HOST}"
    fi
    if [ -n "${N8N_BASIC_AUTH_USER:-}" ] && [ -n "${N8N_BASIC_AUTH_PASSWORD:-}" ]; then
        write_key "N8N_BASIC_AUTH_ACTIVE" "true"
        write_key "N8N_BASIC_AUTH_USER" "${N8N_BASIC_AUTH_USER}"
        write_key "N8N_BASIC_AUTH_PASSWORD" "${N8N_BASIC_AUTH_PASSWORD}"
    fi

    # Port mirrors the unit default (5678); conf wins over it. The `|| true`
    # keeps `set -o pipefail` from aborting when the conf has no PORT= line.
    PORT="${N8N_PORT:-$( { sudo grep -h '^N8N_PORT=' "${CONF}" 2>/dev/null || true; } | tail -n 1 | cut -d= -f2-)}"
    PORT="${PORT:-5678}"

    echo "Enabling n8n.service..."
    sudo systemctl enable --now n8n.service
    echo "Done. The editor UI is at http://127.0.0.1:${PORT} (finish owner-account setup there)."

# Show unit state and whether the editor UI responds.
n8n-status:
    #!/usr/bin/env bash
    set -euo pipefail

    # Port mirrors the unit default (5678); /etc/n8n/n8n.conf wins over it.
    # See n8n-setup for why the `|| true` is needed here.
    CONF="/etc/n8n/n8n.conf"
    PORT="${N8N_PORT:-$( { sudo grep -h '^N8N_PORT=' "${CONF}" 2>/dev/null || true; } | tail -n 1 | cut -d= -f2-)}"
    PORT="${PORT:-5678}"

    echo "Editor UI: http://127.0.0.1:${PORT} (override with N8N_PORT=... or N8N_PORT= in /etc/n8n/n8n.conf)"
    systemctl status n8n.service --no-pager || true
    echo "GET http://127.0.0.1:${PORT}/healthz"
    curl -s --max-time 15 "http://127.0.0.1:${PORT}/healthz" || echo "n8n is not responding on port ${PORT} (still starting, or PORT= mismatch)."
    echo

# Follow the n8n service log.
n8n-logs:
    #!/usr/bin/env bash
    journalctl -u n8n.service -f

# Update n8n to a newer npm release outside the image build, as the n8n user.
# The image stays on its pinned release until the next build; this is for
# trying a fix or a feature early. Pass the version: `ujust n8n-update 2.49.0`.
n8n-update version="":
    #!/usr/bin/env bash
    set -euo pipefail

    VERSION="{{ version }}"
    if [ -z "${VERSION}" ]; then
        echo "Usage: ujust n8n-update <version>  (e.g. ujust n8n-update 2.49.0)" >&2
        exit 1
    fi
    if [ ! -x /usr/lib/n8n/bin/npm ]; then
        echo "Bundled npm missing at /usr/lib/n8n/bin/npm — rebase to an image containing n8n first." >&2
        exit 1
    fi

    echo "Stopping n8n.service..."
    sudo systemctl stop n8n.service
    echo "Updating n8n to v${VERSION}..."
    sudo /usr/lib/n8n/bin/npm install --global --prefix /usr/lib/n8n/app "n8n@${VERSION}"
    echo "Restarting n8n.service..."
    sudo systemctl start n8n.service
    sudo -u n8n /usr/bin/n8n --version
    echo "Done. Pin v${VERSION} as N8N_VERSION in recipes/recipe.yml so the next image build keeps it."
