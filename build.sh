#!/bin/sh
# Cross-kernel (not cross-architecture) build: never use the builder's uname.
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
abi=6.12.118+deb13-amd64
kdir=${KDIR:-/lib/modules/$abi/build}
test "$(cat "$kdir/include/config/kernel.release")" = "$abi"
out=${OUT:-$PWD/dist}; mkdir -p "$out"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
b=$t/sound/soc/intel/boards; mkdir -p "$b" "$t/sound/soc/codecs"
fetch() {
  curl --fail --silent --show-error --location "https://raw.githubusercontent.com/gregkh/linux/v6.12.118/sound/soc/$1" -o "$t/sound/soc/$1"
  printf '%s  %s\n' "$2" "$t/sound/soc/$1" | sha256sum -c -
}
fetch intel/boards/sof_es8336.c 6453e2a124c013785a2ece817b41758f63201e1122b449d953c1a850255b39a9
fetch intel/boards/hda_dsp_common.h f72a3850e0248ea68ba7e6af79268c702b1cee771d11ac04f8f0d9c11dc98f93
fetch codecs/hdac_hda.h 6698e1d51ee53c3dc83b41742ba78f7fb3b4b33f0a0769fd2eb2c34b554d425e
patch --fuzz=0 -d "$b" -p1 < "$repo/inbook-speaker.patch"
cp "$repo/Makefile" "$b/"
make -C "$kdir" M="$b" CONFIG_DEBUG_INFO_BTF_MODULES= modules
ko=$b/snd-soc-sof-es8336.ko
readelf -p .modinfo "$ko" | grep -Fq "vermagic=$abi "
d=$t/package
install -Dm644 "$ko" "$d/lib/modules/$abi/updates/inbook/snd-soc-sof-es8336.ko"
for f in "$repo"/config/*; do
  case ${f##*/} in
    *.service|*.timer) dest=usr/lib/systemd/user ;;
    inbook-x2-audio.conf) dest=etc/modprobe.d ;;
    *) dest=usr/share/alsa/ucm2/conf.d/sof-essx8336 ;;
  esac
  install -Dm644 "$f" "$d/$dest/${f##*/}"
done
mkdir -p "$d/DEBIAN"
cp "$repo"/debian/* "$d/DEBIAN/"
chmod 755 "$d/DEBIAN/postinst" "$d/DEBIAN/postrm"
install -Dm644 "$repo/LICENSE" "$d/usr/share/doc/inbook-x2-audio/copyright"
dpkg-deb --root-owner-group --build "$d" "$out/inbook-x2-audio_1.0.0_amd64.deb"
