# Repository Instructions

- This repository builds a custom Fedora Atomic image with BlueBuild; `recipes/recipe.yml` is the build source of truth.
- The image is based on `ghcr.io/ublue-os/bazzite-dx-gnome` and currently tracks the `latest` image version.
- Build and publish CI runs through `.github/workflows/build.yml` using `blue-build/github-action@v1.11`; signing requires the `SIGNING_SECRET` GitHub secret.
- Changes outside Markdown trigger the push build workflow; pull requests and the daily 06:00 UTC schedule also trigger builds.
- Put files copied into the image under `files/`; paths there mirror their destinations below `/` in the built image.
- `files/system/` contains system files, `files/justfiles/` provides runtime `ujust` recipes, and `files/scripts/` contains scripts intended for recipe integration.
- The `justfiles` module validates files in `files/justfiles/`; the Nix recipes assume the image creates `/nix` during the build and use `ujust nix-setup` when Nix is unavailable.
- The Mudfish version is duplicated in `recipes/recipe.yml` and `files/system/usr/lib/systemd/system/mudfish.service`; update both when changing it.
- Mudfish runtime state is deliberately kept in `/var/lib/mudfish` because `/opt` is read-only at runtime; preserve the service's working directory and `/opt/mudfish/.../var` symlink arrangement.
- Use the README's `rpm-ostree rebase` commands for installation and `cosign verify --key cosign.pub ghcr.io/eirikaskheim/bazzite-dx-gnome` to verify published images.
- Do not commit signing keys or generated `Containerfile`; `.gitignore` excludes `cosign.key`, `cosign.private`, and `/Containerfile`.
