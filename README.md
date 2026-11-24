# Infinix INBOOK X2 speaker fix (Ice Lake, Debian 13)

The headphone jack played normally, but the internal speakers only clicked or produced static. On the tested laptop the patched machine driver, `quirk=128` and a matching ALSA UCM profile restored speaker playback, including after idle and mute/unmute. This is a board-specific workaround, not a general ES8336 driver or a guarantee for other Infinix models.

## Check compatibility first

| Component | v1.0.0 target |
|---|---|
| Laptop | Infinix INBOOK X2, i3-1005G1 (Ice Lake); **not** X2 Plus or X2 Slim |
| DMI board | `EM_IC325_200B_V1.0 20211012`, vendor `Infinix` |
| Audio | ACPI `ESSX8326:00`, Intel SOF Ice Lake, `sof-essx8336` machine card |
| Kernel | Debian 13 amd64 **`6.12.118+deb13-amd64`** |
| Module policy | Unsigned module; requires a kernel permitting unsigned modules. Do not disable Secure Boot just to install this package. |

```sh
cat /sys/class/dmi/id/{sys_vendor,product_name,board_name}  # bash
uname -r
ls -d /sys/bus/acpi/devices/ESSX8326:00
```

## Install

If using [my-opencode](https://github.com/rasyidrafi/my-opencode), apply the updated chezmoi configuration and run `mise run desktop:setup` as your desktop user. It checks compatibility and the pinned release checksum. Otherwise, on the matching system only:

```sh
base=https://github.com/rasyidrafi/inbook-x2-audio/releases/download/v1.0.0
curl -fLO "$base/inbook-x2-audio_1.0.0_amd64.deb"
curl -fLO "$base/SHA256SUMS"
sha256sum -c SHA256SUMS && sudo apt install ./inbook-x2-audio_1.0.0_amd64.deb
systemctl --user daemon-reload
systemctl --user enable --now inbook-audio-login.timer
```

The stock module remains under `kernel/`; the override lives under `updates/inbook/`. Use the **next normal boot** to activate it. Avoid hot-unloading the driver: the headphone GPIO can remain busy and the card can disappear until reboot. If migrating from a manual install, back up local overrides first; same-path files become package-managed. Identically named user units under `~/.config/systemd/user/` take precedence over packaged units.

## Verify and troubleshoot

```sh
modinfo -n snd_soc_sof_es8336       # on-disk selection: .../updates/inbook/...
cat /sys/module/snd_soc_sof_es8336/parameters/quirk   # loaded parameter: 128
cat /proc/asound/cards
pactl get-default-sink              # with jack unplugged: ...HiFi__Speaker__sink
```

Play familiar audio with the jack unplugged; repeat after the sink has idled, and after mute/unmute. A `RUNNING` stream is not proof of audible output. If only `auto_null` appears even though ALSA sees the card, try `systemctl --user restart wireplumber` rather than rebooting. The optional timer checks once after the user session starts and restarts WirePlumber **only** if this card exists and the sole sink is `auto_null`. It is separate from the driver fix. Microphone quality and suspend/resume are not verified.

## What changes

* The [GPIO patch](inbook-speaker.patch) selects the previous headphone GPIO polarity only for the matching Infinix vendor and board. All other boards keep upstream behavior. See [SOF issue #5856](https://github.com/thesofproject/linux/issues/5856) and [upstream GPIO change](https://github.com/torvalds/linux/commit/213c4e51267fd825cd21a08a055450cac7e0b7fb).
* `config/` contains the board-specific UCM controls, module option and login timer. The stock Debian UCM file is not replaced.

## Build on a separate amd64 Debian machine

The builder need not run the laptop kernel. Install `build-essential`, `gcc-14`, `binutils`, `curl`, `patch`, `dpkg-dev` and the **target** Debian kernel headers and their matching kbuild dependencies. From this checkout:

```sh
KDIR=/usr/src/linux-headers-6.12.118+deb13-amd64 ./build.sh
cd dist && sha256sum *.deb > SHA256SUMS
```

The script verifies three source files against pinned hashes from [Linux stable v6.12.118](https://github.com/gregkh/linux/tree/v6.12.118), applies the patch, builds only the machine module, checks its ABI, and packages it. BTF debug metadata is not required. No local DKMS job, proprietary Windows driver, firmware dump or private diagnostic data is included. Upstream code retains its original copyright and licensing; see `LICENSE`.

**Kernel upgrades:** do not copy the `.ko` into a new kernel tree or force-load it. Check whether the new stock kernel already fixes this board; otherwise rebase the patch, update the source hashes, ABI, package dependency/version and maintainer scripts, build against the new headers, and publish a new ABI-specific release. Update the setup integration's version, ABI and checksum. Keep the known working kernel until the new one is tested.

## Roll back

```sh
systemctl --user disable --now inbook-audio-login.timer
sudo apt purge inbook-x2-audio
systemctl --user daemon-reload
modinfo -n snd_soc_sof_es8336  # should now resolve under kernel/, not updates/inbook/
```

Boot normally to load the stock driver again. Purging removes package-managed files, not user-created overrides. On a manually customized initramfs that embeds the module, regenerate it for the target kernel after installation or removal.
