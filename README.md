# bazzite-dx-gnome &nbsp; [![bluebuild build badge](https://github.com/eirikaskheim/bazzite-dx-gnome/actions/workflows/build.yml/badge.svg)](https://github.com/eirikaskheim/bazzite-dx-gnome/actions/workflows/build.yml)

See the [BlueBuild docs](https://blue-build.org/how-to/setup/) for quick setup instructions for setting up your own repository based on this template.

After setup, it is recommended you update this README to describe your custom image.

## Installation

> [!WARNING]  
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/eirikaskheim/bazzite-dx-gnome:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/eirikaskheim/bazzite-dx-gnome:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## Local LLM AMD GPU tuning

The image includes AMD GPU settings intended to improve the amount of host memory available to local LLM workloads. The settings are installed as part of the image in:

- `/etc/modprobe.d/amdgpu_llm_optimized.conf`
- `/etc/udev/rules.d/99-amd-kfd.rules`

After rebasing to an image containing these files, run the following as the user who will run the LLM workloads:

```bash
ujust llm-gpu-setup
systemctl reboot
```

The setup recipe uses `dracut` (the Fedora/Bazzite equivalent of Ubuntu's `update-initramfs`), reloads the udev rules, and adds the user to the `render` and `video` groups. The group changes require logging in again. The udev rules grant render and KFD device access to all local users, so only use this image on systems where that is acceptable.

## OpenViking server

OpenViking is installed in an isolated virtual environment at `/usr/lib/openviking/venv`.
The `ov` and `openviking-server` commands are linked into `/usr/bin`. The system
service runs as the unprivileged `openviking` system user and stores its configuration
and data in its writable `/var/lib/openviking` home directory. The account and directory
are created at boot by `systemd-sysusers` and `systemd-tmpfiles`, including after image
updates.

After rebasing, run the interactive setup and start the service:

```bash
ujust openviking-server-init
```

Validate the configuration and provider connectivity with:

```bash
ujust openviking-server-doctor
```

The service can then be managed with `systemctl status|restart openviking-server`.
It is intentionally not enabled by default until the initialization recipe completes.

## Mudfish VPN

Mudfish runs as the `mudfish` systemd service (`mudfish.service`, headless). Its
runtime state lives in `/var/lib/mudfish` and its web UI is served at
[http://127.0.0.1:8282](http://127.0.0.1:8282).

The service wrapper keeps Mudfish's **Auto Connect** setting (Launcher
`Setup -> Program -> Launcher -> Auto Connect`) enabled, so the daemon starts
its core processes immediately after the sign-in event. To also sign in at
boot without opening the web UI, store your credentials once with:

```bash
ujust mudfish-setup
```

This writes your Mudfish account and password to `/etc/mudfish/credentials`
(root-only; it is never part of the image) and restarts the service. After a
reboot Mudfish should sign in and connect on its own. Check with:

```bash
systemctl status mudfish --no-pager
ps -ef | grep -E 'mudfish|mudflow'   # cores running = connected
```

To stop Mudfish connecting at startup, remove the credentials file and/or
turn off Auto Connect in the web UI:

```bash
sudo rm /etc/mudfish/credentials
```

## Backups (restic → bokhylla)

The image includes restic and a `ujust restic-*` recipe set for encrypted,
incremental backups over SSH to the `bokhylla` home server (restic `sftp`
backend, repository stored on the `tank` ZFS pool). On bokhylla the
repository lives in its own dataset (`tank/pc/bazzite`), alongside the other
PC backups under `tank/pc/`.

One-time setup, run after rebase (or before the next rebase directly from a
repo checkout with `just -f files/justfiles/restic.just restic-setup`):

```bash
ujust restic-setup
```

It prompts for the backup host and repository path (defaults:
`eirik@bokhylla`, `/tank/pc/bazzite/restic`), generates a repository
passphrase, and stores everything root-only in `/etc/restic/` plus a
dedicated SSH key in `/root/.ssh/`. The backup key is authorized on bokhylla
automatically over your existing SSH access. The remote directory must be
writable by the remote account; on bokhylla it was created once with:

```bash
ssh bokhylla 'sudo zfs create tank/pc/bazzite && sudo chown eirik:users /tank/pc/bazzite'
```

Then run backups on demand:

```bash
ujust restic-backup      # /etc, /var/lib and your home directory
ujust restic-snapshots   # list stored snapshots
ujust restic-check       # verify repository integrity
```

Each backup stores one snapshot containing `/etc`, `/var/lib` and the
invoking user's home directory. Caches and regenerable data are excluded
(see `/etc/restic/excludes`): `~/.cache`, `Trash`, `~/.npm`, `~/.rustup`,
the Cargo registry cache, Steam shader caches, system Flatpaks and container
image storage. The restic repository passphrase printed by `restic-setup` is
stored root-only in `/etc/restic/password`; keep a copy in your password
manager — without it the repository cannot be read.

To restore a snapshot, use restic directly as root (the repository
configuration lives in `/etc/restic/env`):

```bash
sudo bash -c 'set -a; . /etc/restic/env; set +a; exec restic restore latest --target /'
```

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/how-to/generate-iso/#_top). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/eirikaskheim/bazzite-dx-gnome
```
