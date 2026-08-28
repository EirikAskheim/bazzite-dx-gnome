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
service runs as the unprivileged `openviking` user and stores its configuration and data
in its writable `/var/lib/openviking` home directory.

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

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/how-to/generate-iso/#_top). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/eirikaskheim/bazzite-dx-gnome
```
