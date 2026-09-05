#!/bin/bash
#
# mudfish-run.sh - launcher for the Mudfish headless daemon (mudfish.service)
#
# Started at boot by systemd (WorkingDirectory=/var/lib/mudfish). It makes
# Mudfish sign in and connect on its own, without the web UI:
#
#  1. Forces the launcher's "Auto Connect" flag on in the state file
#     (/var/lib/mudfish/.conf). After the sign-in event the launcher then
#     starts its core processes (mudfish, mudflow) automatically, i.e. the
#     equivalent of pressing Connect in the web UI.
#
#  2. When /etc/mudfish/credentials exists (root-only; provisioned with
#     `ujust mudfish-setup`) the daemon is started with -u/-p so it signs in
#     by itself at boot. Auto Connect then takes over from there.
#
# Without a credentials file the daemon behaves as before: the user signs in
# through the web UI at http://127.0.0.1:8282 and Connect happens
# automatically after that sign-in.

set -u

STATE_DIR="/var/lib/mudfish"
CONF_FILE="${STATE_DIR}/.conf"
CRED_FILE="/etc/mudfish/credentials"
MUD_BIN="/usr/bin/mudrun-headless"

if [ ! -x "${MUD_BIN}" ]; then
    echo "mudfish-run: ${MUD_BIN} not found; is Mudfish installed?" >&2
    exit 1
fi

# The daemon reads its launcher parameters from .conf in its working
# directory at startup, so keep Auto Connect enabled there.
if [ -f "${CONF_FILE}" ]; then
    if grep -q '^mudrun\.autoconnect[[:space:]]' "${CONF_FILE}"; then
        sed -i 's|^mudrun\.autoconnect[[:space:]].*|mudrun.autoconnect \t on|' "${CONF_FILE}"
    else
        printf 'mudrun.autoconnect \t on\n' >> "${CONF_FILE}"
    fi
else
    printf 'mudrun.autoconnect \t on\n' >> "${CONF_FILE}"
fi

# -B: don't open a browser. -u/-p: sign in automatically at startup.
set -- "${MUD_BIN}" -B
if [ -r "${CRED_FILE}" ]; then
    # shellcheck disable=SC1090
    . "${CRED_FILE}"
    if [ -n "${MUD_USERNAME:-}" ] && [ -n "${MUD_PASSWORD:-}" ]; then
        set -- "$@" -u "${MUD_USERNAME}" -p "${MUD_PASSWORD}"
    fi
fi

exec "$@"
