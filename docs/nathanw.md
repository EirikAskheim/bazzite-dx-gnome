# Nathanw llama-server (Strix Halo Vulkan, portable tarball)

Native `llama-server` from the upstream performance fork
[Nathanw1014/strix-halo-llamacpp](https://github.com/Nathanw1014/strix-halo-llamacpp),
running as the `nathanw-llama-server` system service on port 8080.
No containers, no model router — clients talk OpenAI-compatible HTTP
directly to `http://127.0.0.1:8080/v1`.

## Source and version

- Upstream repo: <https://github.com/Nathanw1014/strix-halo-llamacpp>
- Install method: the **portable Vulkan tarball**
  (`strix-halo-llamacpp-vulkan-portable.tar.gz`), which bundles Mesa RADV +
  libdrm, so the host only needs the Vulkan loader and `/dev/dri` access.
  The tarball's `_run` wrapper pins `VK_ICD_FILENAMES` / `LD_LIBRARY_PATH`
  to the bundled driver — the service unit must never override them.
- **Pinned version: v0.7.5** (2026-09-09; latest release as of 2026-09-12,
  verified via the GitHub tags/releases API; tarball listing, `_run`
  wrapper, and `MANIFEST.txt` inspected from the actual artifact).
- The pin lives in exactly one place: `VERSION=` in the Nathanw block of
  `recipes/recipe.yml`. (Watch [halo-box/strix-llama.cpp](https://github.com/halo-box/strix-llama.cpp):
  upstream says Vulkan work is migrating there, so the tarball source may
  move in the future.)

## What the repo files do

| Repo path | Deploys to | Purpose |
| --- | --- | --- |
| `recipes/recipe.yml` (Nathanw block) | image build | Downloads the pinned tarball, extracts to `/usr/lib/nathanw/`, symlinks `/usr/bin/llama-server-nathanw` (plus `-bench`/`-cli`), smoke-tests `--version` |
| `files/system/usr/lib/systemd/system/nathanw-llama-server.service` | `/usr/lib/systemd/system/` | Service unit: runs as `nathanw`, gated on `/var/lib/nathanw/.models-ready`, reads `/etc/nathanw/llama-server.conf` over baked-in defaults |
| `files/system/usr/lib/sysusers.d/nathanw.conf` | `/usr/lib/sysusers.d/` | `nathanw` user (`/sbin/nologin`, home `/var/lib/nathanw`) + `render`/`video` membership |
| `files/system/usr/lib/tmpfiles.d/nathanw.conf` | `/usr/lib/tmpfiles.d/` | `/var/lib/nathanw`, `models/`, `slots/` owned by `nathanw` |
| `files/justfiles/nathanw.just` | `ujust` | `nathanw-models-download`, `nathanw-setup`, `nathanw-verify`, `nathanw-bench`, `nathanw-logs`, `nathanw-status` |
| `files/system/etc/restic/excludes` (`/var/lib/nathanw/models`) | `/etc/restic/excludes` | Keeps the ~100 GiB re-downloadable weights out of backups |

Deliberately **not** preset-enabled: a fresh image has no weights, so the
service would only crash-loop. `ujust nathanw-setup` enables + starts it
after the download, and `ConditionPathExists=/var/lib/nathanw/.models-ready`
guards against accidental starts.

## First-time setup

```bash
ujust nathanw-setup     # downloads ~100 GiB (takes a long time), disables ollama, enables+starts the service
ujust nathanw-logs      # follow the slow mmap-heavy model load
ujust nathanw-verify    # /health + tiny chat completion
```

Notes:

- `nathanw-setup` **disables `ollama.service`**: both preloaded at once
  exhaust GTT on unified memory and die with `vk::DeviceLostError`.
- `nathanw-models-download` needs ≥ 120 GiB free (override with
  `NATHANW_SKIP_DISK_CHECK=1`), is resumable, and accepts
  `NATHANW_MODEL_REPO` / `NATHANW_MODEL_INCLUDE` overrides for a different
  quant. It verifies shard 1 exists (33/33 shards for the default
  AD-4.27bpw set) and writes `/etc/nathanw/llama-server.conf`
  (`MODEL=` + `EXTRA_ARGS=` with `-md` MTP sidecar and `--mmproj`).
- Default weights (128 GB box): AtomicChat AD-4.27bpw `Q4_K_M-M64`,
  33 shards (~93 GiB), plus Unsloth **shared** MTP head
  (`mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf`, ~2.8 GB — v0.7.5 expects the
  shared head, not the old self-contained one) and the `mmproj-F16`
  projector. `-m` points only at shard `00001-of-00033`; keep all shards
  in one directory, do not rename.
- The unit's baked-in flags follow upstream's Flash-Next guidance:
  `-ngl 99 --n-cpu-moe 0 -fa on`, mandatory
  `--load-mode mmap --no-host --no-repack --fit off` (the ~95 GiB PLE
  table must stay memory-mapped, never allocated), `--ctx-size 131072`
  (raise to 262144 once stable), `q8_0` KV (`q4_0` for maximum context),
  slot saves under `/var/lib/nathanw/slots/`. Override via `EXTRA_ARGS=`
  in `/etc/nathanw/llama-server.conf` (e.g. a different `--n-cpu-moe` for
  64 GB boxes, where MTP needs headroom at `--n-cpu-moe 4+`).

## Day-to-day use

```bash
ujust nathanw-status    # unit state + /health
ujust nathanw-logs      # follow logs
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":32}'
```

The service binds `127.0.0.1:8080` (local-only). For LAN access, add
`--host 0.0.0.0` via `EXTRA_ARGS` in `/etc/nathanw/llama-server.conf`
and restart — only if you actually want it reachable.

## Updating to a new upstream version

1. Check what is new: compare
   <https://github.com/Nathanw1014/strix-halo-llamacpp/releases/latest>
   against the pinned `VERSION`; read the release notes for flag changes,
   slot-save incompatibilities (e.g. v0.7.4 → v0.7.5 slot files do not
   restore — wipe `/var/lib/nathanw/slots/` and accept one re-prefill),
   and any new MTP/model requirements.
2. Bump `VERSION=` in the Nathanw block of `recipes/recipe.yml`.
   If the release renamed the portable asset, update the tarball URL in
   the same block. If it changed shard layouts or flag requirements,
   update the defaults in `nathanw-llama-server.service` and the download
   layout in `files/justfiles/nathanw.just` to match.
3. Rebuild the image (push / PR — any non-Markdown change triggers
   `.github/workflows/build.yml`), rebase, reboot.
4. Re-run `ujust nathanw-models-download` so
   `/etc/nathanw/llama-server.conf` agrees with the new binary, then
   `sudo systemctl restart nathanw-llama-server.service`.
5. Verify: `ujust nathanw-verify`, plus the bundled-driver check from
   upstream — `llama-bench-nathanw …` must show `backend = Vulkan` and a
   `ggml_vulkan: 0 = …RADV STRIX_HALO` line (not CPU fallback). For a
   numbers comparison, stop the service and run `ujust nathanw-bench`
   (baseline: same `-p 512 -n 32 -d 0,32768` command before and after).
6. Update the pin + date in this file's "Source and version" section.
