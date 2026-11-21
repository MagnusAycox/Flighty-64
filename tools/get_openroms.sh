#!/bin/sh
# Hämtar MEGA65 Open ROMs: fria ersättare (LGPL-3) för C64:ans KERNAL,
# BASIC och teckengenerator. Används av tools/vice_test.py när originalens
# ROM:ar inte finns (t.ex. Debian/Ubuntus VICE-paket saknar dem).
# Källa: https://github.com/MEGA65/open-roms
set -e
cd "$(dirname "$0")/.."
DIR=build/openroms
URL=https://raw.githubusercontent.com/MEGA65/open-roms/master
mkdir -p "$DIR"
for f in bin/kernal_generic.rom bin/basic_generic.rom bin/chargen_openroms.rom LICENSE; do
    curl -fsSL -o "$DIR/$(basename $f)" "$URL/$f"
done
echo "Open ROMs i $DIR"
