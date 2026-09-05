# Repository Instructions

- This repository builds a custom Fedora Atomic image with BlueBuild; `recipes/recipe.yml` is the build source of truth.
- The image is based on `ghcr.io/ublue-os/bazzite-dx-gnome` and currently tracks the `latest` image version.
- Build and publish CI runs through `.github/workflows/build.yml` using `blue-build/github-action@v1.11`; signing requires the `SIGNING_SECRET` GitHub secret.
- Changes outside Markdown trigger the push build workflow; pull requests and the daily 06:00 UTC schedule also trigger builds.
- Put all generated reports and project documentation in `docs/`.
- Put files copied into the image under `files/`; paths there mirror their destinations below `/` in the built image.
- `files/system/` contains system files, `files/justfiles/` provides runtime `ujust` recipes, and `files/scripts/` contains scripts intended for recipe integration.
- The `justfiles` module validates files in `files/justfiles/`; the Nix recipes assume the image creates `/nix` during the build and use `ujust nix-setup` when Nix is unavailable.
- The Mudfish version is set in `recipes/recipe.yml` only; `/usr/bin/mudrun-headless` (created there) resolves the install at runtime. The `mudfish.service` unit launches the `/usr/libexec/mudfish-run.sh` wrapper, which resolves the binary via `/usr/bin`.
- The `mudfish-run.sh` wrapper enforces the launcher's Auto Connect flag (`mudrun.autoconnect on` in the state `.conf`) at every start, so the daemon connects right after its sign-in event. Boot-time sign-in needs credentials in `/etc/mudfish/credentials` (root-only, provisioned with `ujust mudfish-setup`; never commit them or bake them into the image).
- Mudfish runtime state is deliberately kept in `/var/lib/mudfish` because `/opt` is read-only at runtime; preserve the service's working directory and `/opt/mudfish/.../var` symlink arrangement, and keep the wrapper writing Auto Connect only into `/var/lib/mudfish/.conf`.
- Use the README's `rpm-ostree rebase` commands for installation and `cosign verify --key cosign.pub ghcr.io/eirikaskheim/bazzite-dx-gnome` to verify published images.
- Do not commit signing keys or generated `Containerfile`; `.gitignore` excludes `cosign.key`, `cosign.private`, and `/Containerfile`.
