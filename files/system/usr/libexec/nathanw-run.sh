#!/usr/bin/env bash
#
# nathanw-run.sh - launcher for nathanw-llama-server.service
#
# systemd does NOT word-split variables expanded in ExecStart= (an expanded
# ${EXTRA_ARGS} stays a single argv element), so the unit cannot pass
# `-md <draft> --mmproj <proj>` through the environment directly — the
# server dies with `error: invalid argument: -md ... --mmproj ...`.
# The unit therefore execs this wrapper instead and lets the shell split
# EXTRA_ARGS here (MODEL stays quoted; it is always a single path).
#
# Configuration comes from the service's Environment=/EnvironmentFile=
# (/etc/nathanw/llama-server.conf, written by `ujust nathanw-models-download`
# over the unit's baked-in defaults), so model switches survive image updates.

set -u

: "${MODEL:?MODEL is not set — run 'ujust nathanw-models-download' first.}"
: "${EXTRA_ARGS:=}"

# shellcheck disable=SC2086 (EXTRA_ARGS is intentionally word-split here)
exec /usr/lib/nathanw/vulkan/llama-server \
    --host 127.0.0.1 --port 8080 \
    -m "$MODEL" \
    -ngl 99 --n-cpu-moe 0 -fa on \
    --load-mode mmap --no-host --no-repack --fit off \
    --ctx-size 131072 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --slot-save-path /var/lib/nathanw/slots \
    $EXTRA_ARGS
