<p align="center">
  <img src="docs/logo.svg" alt="void-workstation" width="132" height="132">
</p>

<h1 align="center">void-workstation</h1>

<p align="center">
  A repeatable <b>Niri + DankMaterialShell</b> desktop for Void Linux.<br>
  One command installs the session, theme, fonts, audio stack and defaults on a clean system.
</p>

<p align="center">
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-a6c8ff"></a>
  <a href="https://voidlinux.org"><img alt="platform" src="https://img.shields.io/badge/platform-Void%20Linux-478061"></a>
  <a href="install.sh"><img alt="shell" src="https://img.shields.io/badge/shell-POSIX%20sh-4e5d6c"></a>
  <a href="https://github.com/Senyacka/void-workstation-setup/actions/workflows/check.yml"><img alt="check" src="https://github.com/Senyacka/void-workstation-setup/actions/workflows/check.yml/badge.svg"></a>
</p>

## What you get

| | |
|---|---|
| **Session** | niri (scrollable tiling), DankMaterialShell on Quickshell, fuzzel launcher, greetd login screen |
| **Look** | Material palette from DMS, adw-gtk3 + glass Thunar, Roboto & FiraCode, animated lock screen |
| **Sound** | PipeWire + WirePlumber under user runit, with a watchdog that restarts a stuck stack |
| **System** | portals (file chooser, screencast, secrets), power and fan helpers, dconf defaults, runit services |
| **Tools** | kitty, Thunar, `healthcheck`, `theme-sync`, `fanmode`, `power-log` |

## Requirements

| | |
|---|---|
| OS | Void Linux, x86_64, glibc — installed and booted |
| User | member of `wheel`, passwordless sudo (`sudo -n true` works) |
| Network | ~1.5 GB of packages from the Void and DankLinux repositories |
| Disk | 8 GB free on `/` |

## Install

**From a USB stick** (built with `./make-usb.sh`, see below):

```sh
sudo mount /dev/sdX1 /mnt/usb
sh /mnt/usb/void-workstation/install.sh
```

**From the internet** (fresh Void has no `git`/`curl`, so install them first):

```sh
sudo xbps-install -Sy curl tar
git clone https://github.com/Senyacka/void-workstation-setup.git
cd void-workstation-setup && ./install.sh
```

Without git:

```sh
curl -L https://github.com/Senyacka/void-workstation-setup/archive/refs/heads/main.tar.gz | tar xz
cd void-workstation-setup-main && sh install.sh
```

Single self-extracting file (attach to a release with `./tools/mkrun.sh`):

```sh
curl -LO https://github.com/Senyacka/void-workstation-setup/releases/latest/download/void-workstation.run
sh void-workstation.run
```

**Unattended.** The menu saves its answers to
`~/.local/state/void-workstation/menu.conf`; `./install.sh` picks that file up
automatically. To drive it from your own file, start from the example:

```sh
cp install.conf.example install.conf        # user, hostname, timezone, packages
./install.sh --config install.conf --yes    # apply without questions
./install.sh --config install.conf --dry-run   # print the plan, change nothing
./install.sh --only packages                # run a single stage
```

## What it does

`repos → packages → system → services → home → assets → session → grub → dms → verify`

- `system` copies only files that **differ from the packaged defaults** (checked by
  xbps checksums, currently 17 files) and keeps a backup next to each original as
  `<name>.pre-setup.<date>`.
- `grub` sets the kernel parameters in `/etc/default/grub` (zswap, `preempt=full`,
  CPU/GPU options); the GRUB menu is regenerated only with `--grub`.
- `session` switches the login to `greetd` (`dms-greeter` or `tuigreet`); revert with
  `sudo rm /var/service/greetd` — consoles `tty2…tty6` stay available.
- `verify` compares the result with the configuration and prints what is missing.

It does **not** partition disks, install the OS, create users or set passwords —
`void-installer` does that. Passwordless sudo for `wheel` is enabled by
`system/root/etc/sudoers.d/wheel`; delete that file before installing if unwanted.

## Menu

| Keys | Action |
|---|---|
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | move around |
| `Space` | toggle a package — or the whole group on a group row |
| `Enter` / `Esc` | confirm / go back |
| `Tab` | switch buttons, next form field |

## Hardware support

Everything is detected at runtime (`lib/hwdetect.sh`); unsupported parts are skipped
instead of failing.

| Detected | Enabled |
|---|---|
| Intel CPU | `intel-ucode`, turbo and RAPL limits |
| AMD CPU | `linux-firmware-amd`, `amd_pstate=active`, RAPL part disabled |
| Intel GPU | VA-API (`intel-media-driver`), Vulkan, `xe.force_probe` for affected GPUs |
| AMD GPU | `mesa-vaapi`, `mesa-vulkan-radeon` |
| NVIDIA GPU | `nvidia` from nonfree, `nvidia-drm.modeset=1` |
| Battery with a charge threshold | charge limit helper and udev rule |
| `platform_profile` / `hwmon` fan | power profiles, `fanmode` |
| Virtual machine | power and thermal checks are skipped |

## Maintenance

| Command | Purpose |
|---|---|
| `./verify.sh` | compare this machine with the configuration |
| `healthcheck` | session, audio, power, updates — `--hints`, `--json`, `--quiet` |
| `./collect.sh` | snapshot this machine back into the repository |
| `make check` | syntax, package names, descriptions, no leaked secrets |
| `./make-usb.sh /mnt/usb` | build a stick with only the runtime files (`--dry-run`, `--no-assets`) |
| `./tools/mkrun.sh out.run` | pack everything into one self-extracting file |

## Limitations

- DMS regenerates `niri/dms/*.kdl`, `gtk-*/dank-colors.css` and `kitty/dank-*.conf`;
  re-run `theme-sync dark` after changing the theme.
- DMS plugins are restored from `plugins.lock.json` and need network and `git`.
- NVIDIA is the riskiest path: firmware and kernel options are set, but keep a second
  kernel entry with `nomodeset` as a fallback.

## Layout

```
install.sh menu.sh ui.sh detect.sh verify.sh make-usb.sh   entry points
lib/ lang/                                                 shared code and UI strings
packages/                                                  core, hardware, optional groups + descriptions
tools/                                                     publisher side: scan, pack, checks
system/{root/,MANIFEST}                                    files for /etc and their checksums
home/                                                      dotfiles, themes, fonts
assets/ presets/ docs/                                     lock-screen video, presets, logo
```

## License

Code and configuration: [MIT](LICENSE). Bundled third-party resources keep their
upstream licenses: the adw-gtk3 themes, FiraCode and Google Sans Flex fonts
(SIL OFL 1.1, license text is included) and the lock-screen video built from Pexels
footage (Pexels License). Packages come from the Void Linux and DankLinux
repositories.
