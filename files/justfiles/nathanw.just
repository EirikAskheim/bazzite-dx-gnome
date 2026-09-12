# Nathanw llama-server (Strix Halo Vulkan, portable tarball) runtime recipes.
# The binary itself is baked into the image by recipes/recipe.yml (VERSION is
# pinned there). These recipes fetch weights into /var/lib/nathanw/models as
# the nathanw service account, write /etc/nathanw/llama-server.conf, and manage
# the nathanw-llama-server service. See docs/nathanw.md for the full picture.

# Download (or re-check) all weights, write the service config, and mark the
# model tree ready. Resumable; safe to re-run. Env overrides:
# NATHANW_MODEL_REPO, NATHANW_MODEL_INCLUDE, NATHANW_SKIP_DISK_CHECK=1.
nathanw-models-download:
    #!/usr/bin/env bash
    set -euo pipefail

    REPO="${NATHANW_MODEL_REPO:-AtomicChat/Qwen3.8-Flash-Next-GGUF}"
    INCLUDE="${NATHANW_MODEL_INCLUDE:-Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64/*}"
    SUBDIR="Qwen3.8-Flash-Next"
    MODELS_DIR="/var/lib/nathanw/models"
    TARGET_DIR="${MODELS_DIR}/${SUBDIR}"
    # v0.7.5 expects the shared MTP head (2.79 GB), not the old self-contained one.
    MTP_INCLUDE="MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf"
    MMPROJ_INCLUDE="mmproj-Qwen3.8-Flash-Next-F16.gguf"
    SHARD1="Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64/Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64-00001-of-00033.gguf"

    if [ ! -x /usr/lib/nathanw/vulkan/llama-server ]; then
        echo "Nathanw binary missing at /usr/lib/nathanw — rebase to an image containing it first." >&2
        exit 1
    fi

    if [ "${NATHANW_SKIP_DISK_CHECK:-0}" != "1" ]; then
        # MODELS_DIR is 0750 nathanw:nathanw, so an unprivileged df on it
        # fails with "Permission denied"; check via sudo (the rest of this
        # recipe needs sudo anyway).
        AVAIL_GB="$(sudo df --output=avail -BG "${MODELS_DIR}" | tail -n 1 | tr -dc '0-9')"
        if [ "${AVAIL_GB}" -lt 120 ]; then
            echo "Only ${AVAIL_GB} GiB free under ${MODELS_DIR}; need >= 120 GiB." >&2
            echo "Free space, point weights elsewhere, or set NATHANW_SKIP_DISK_CHECK=1." >&2
            exit 1
        fi
    fi

    download() {
        sudo -H -u nathanw env HF_HUB_ENABLE_HF_TRANSFER=1 \
            uvx --from 'huggingface_hub[hf_transfer]' hf download "$@"
    }

    echo "Downloading main weights (${REPO} :: ${INCLUDE})..."
    download "${REPO}" --include "${INCLUDE}" --local-dir "${TARGET_DIR}"
    echo "Downloading MTP draft sidecar..."
    download unsloth/Qwen3.8-Flash-Next-GGUF \
        --include "${MTP_INCLUDE}" --local-dir "${TARGET_DIR}"
    echo "Downloading vision projector..."
    download "${REPO}" --include "${MMPROJ_INCLUDE}" --local-dir "${TARGET_DIR}"

    # llama.cpp resolves shards relative to shard 1; it must exist.
    if ! sudo -u nathanw test -f "${TARGET_DIR}/${SHARD1}"; then
        echo "Shard 1 missing at ${TARGET_DIR}/${SHARD1}; download is incomplete." >&2
        exit 1
    fi
    if [ "${REPO}" = "AtomicChat/Qwen3.8-Flash-Next-GGUF" ] && \
       [ "${INCLUDE}" = "Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64/*" ]; then
        COUNT="$(sudo -u nathanw bash -c "ls '${TARGET_DIR}/Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64/' | wc -l")"
        if [ "${COUNT}" -ne 33 ]; then
            echo "Expected 33 shards, found ${COUNT}; download is incomplete." >&2
            exit 1
        fi
    fi

    # The unit reads this file (EnvironmentFile) over its baked-in defaults,
    # so the model path stays in writable /etc across image updates.
    sudo install -d -m 755 /etc/nathanw
    printf 'MODEL=%s\nEXTRA_ARGS=-md %s --mmproj %s\n' \
        "${TARGET_DIR}/${SHARD1}" \
        "${TARGET_DIR}/${MTP_INCLUDE}" \
        "${TARGET_DIR}/${MMPROJ_INCLUDE}" | \
        sudo tee /etc/nathanw/llama-server.conf >/dev/null
    # Sentinel the service's ConditionPathExists gates on.
    sudo -u nathanw touch /var/lib/nathanw/.models-ready
    echo "Wrote /etc/nathanw/llama-server.conf and marked models ready."

# One-shot setup after rebase: download weights, retire Ollama (both preloaded
# at once exhaust GTT and die with vk::DeviceLostError), then enable and start
# the service. The multi-GB download takes a long time; start it and walk away.
nathanw-setup: nathanw-models-download
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Disabling Ollama (Ollama + Nathanw preloaded together exhaust GTT)..."
    sudo systemctl disable --now ollama.service || true
    echo "Enabling nathanw-llama-server..."
    sudo systemctl enable --now nathanw-llama-server.service
    echo "Done. Follow the (slow, ~100 GiB mmap) load with: ujust nathanw-logs"

# Check the service is up and serving: /health plus a tiny chat completion.
nathanw-verify:
    #!/usr/bin/env bash
    set -euo pipefail

    # Port mirrors nathanw-run.sh / the unit default (8082); override with
    # PORT= in the environment (reads /etc/nathanw/llama-server.conf first).
    PORT="${PORT:-$(grep -h '^PORT=' /etc/nathanw/llama-server.conf 2>/dev/null | tail -n 1 | cut -d= -f2-)}"
    PORT="${PORT:-8082}"
    BASE="http://127.0.0.1:${PORT}"
    systemctl is-active nathanw-llama-server.service
    curl --fail -s "${BASE}/health"
    echo
    curl --fail -s "${BASE}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d '{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":32}'
    echo

# Baseline benchmark for comparing releases after upgrades. Stop the service
# first so the benchmark has the GPU to itself; see docs/nathanw.md.
nathanw-bench:
    #!/usr/bin/env bash
    set -euo pipefail

    if systemctl is-active --quiet nathanw-llama-server.service; then
        echo "Stop the service first so the benchmark owns the GPU:" >&2
        echo "  sudo systemctl stop nathanw-llama-server.service" >&2
        exit 1
    fi
    [ -f /etc/nathanw/llama-server.conf ] && . /etc/nathanw/llama-server.conf
    : "${MODEL:?/etc/nathanw/llama-server.conf missing — run 'ujust nathanw-models-download' first.}"
    /usr/bin/llama-bench-nathanw -m "${MODEL}" \
        -ngl 99 --n-cpu-moe 0 -fa 1 -p 512 -n 32 -d 0,32768

# Follow the service log (model load, requests, errors).
nathanw-logs:
    #!/usr/bin/env bash
    journalctl -u nathanw-llama-server.service -f

# One-line service + API status.
nathanw-status:
    #!/usr/bin/env bash
    set -euo pipefail

    # Port mirrors nathanw-run.sh / the unit default (8082); override with
    # PORT= in the environment (reads /etc/nathanw/llama-server.conf first).
    PORT="${PORT:-$(grep -h '^PORT=' /etc/nathanw/llama-server.conf 2>/dev/null | tail -n 1 | cut -d= -f2-)}"
    PORT="${PORT:-8082}"
    systemctl status nathanw-llama-server.service --no-pager || true
    curl -s "http://127.0.0.1:${PORT}/health" || echo "API not responding."
    echo
