# Apply the per-user AMD GPU access and regenerate the initramfs after installing
# or rebasing to an image containing the LLM tuning configuration.
llm-gpu-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "Run 'ujust llm-gpu-setup' as the user who will run the LLM workloads, not as root." >&2
        exit 1
    fi

    CURRENT_USER="$(id -un)"
    added_group=0

    # Check that the groups exist in the system database. These checks are
    # deliberately not membership checks: membership is what we add below.
    if ! getent group render >/dev/null; then
        echo "The render group is not present; refusing to configure GPU access." >&2
        exit 1
    fi
    if ! getent group video >/dev/null; then
        echo "The video group is not present; refusing to configure GPU access." >&2
        exit 1
    fi

    if ! id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx render; then
        sudo usermod -aG render "$CURRENT_USER"
        added_group=1
    fi
    if ! id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx video; then
        sudo usermod -aG video "$CURRENT_USER"
        added_group=1
    fi

    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=kfd --subsystem-match=drm

    # Unlike Ubuntu's update-initramfs, Fedora/Bazzite uses dracut. Rebuild it
    # so amdgpu sees the options even when it is loaded from the initramfs.
    sudo dracut --regenerate-all --force

    echo "AMD GPU LLM tuning is configured. Reboot to load the new amdgpu options."
    if [[ "$added_group" -eq 1 ]]; then
        echo "Your render/video group membership will take effect after logging in again."
    fi
