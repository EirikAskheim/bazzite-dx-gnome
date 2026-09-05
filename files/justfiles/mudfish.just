# Store Mudfish sign-in credentials (root-only) and restart the daemon so it
# signs in and connects automatically at boot. The credentials file lives in
# /etc (writable, persisted across updates) and is never baked into the image.
mudfish-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    CRED_FILE="/etc/mudfish/credentials"

    echo "Mudfish auto-connect setup"
    echo "--------------------------"
    echo "The credentials are stored root-only in ${CRED_FILE} and are used"
    echo "by mudfish.service at boot to sign in automatically. 'Auto Connect'"
    echo "is already forced on by the service wrapper, so after sign-in the"
    echo "VPN connects without touching the web UI."
    echo

    read -r -p "Mudfish account (e-mail): " MUD_USERNAME
    if [ -z "${MUD_USERNAME}" ]; then
        echo "No account given, aborting." >&2
        exit 1
    fi

    read -r -s -p "Mudfish password: " MUD_PASSWORD
    echo
    if [ -z "${MUD_PASSWORD}" ]; then
        echo "No password given, aborting." >&2
        exit 1
    fi

    sudo install -d -m 700 /etc/mudfish
    printf 'MUD_USERNAME=%q\nMUD_PASSWORD=%q\n' "${MUD_USERNAME}" "${MUD_PASSWORD}" | \
        sudo tee "${CRED_FILE}" >/dev/null
    sudo chown root:root "${CRED_FILE}"
    sudo chmod 600 "${CRED_FILE}"
    echo "Credentials saved to ${CRED_FILE} (root-only)."

    echo "Restarting mudfish.service..."
    sudo systemctl restart mudfish.service

    echo
    echo "Done. Give the daemon a moment, then check it connected with:"
    echo "  systemctl status mudfish --no-pager"
    echo "  ps -ef | grep -E 'mudfish|mudflow'   # cores running = connected"
    echo "Or open http://127.0.0.1:8282 in a browser."
