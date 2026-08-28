# Configure OpenViking as its service account, then enable and start the server.
openviking-server-init:
    #!/usr/bin/env bash
    set -euo pipefail

    sudo systemctl stop openviking-server.service
    sudo -H -u openviking /usr/bin/openviking-server init
    sudo systemctl enable --now openviking-server.service

# Validate OpenViking's configuration and provider connectivity as the service account.
openviking-server-doctor:
    #!/usr/bin/env bash
    set -euo pipefail

    sudo -H -u openviking /usr/bin/openviking-server doctor
