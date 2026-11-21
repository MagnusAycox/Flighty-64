#!/bin/sh
# Bygger Flighty 64 med KickAssembler.
#
#   ./build.sh                      (KickAss.jar letas upp via $KICKASS)
#   KICKASS=/sökväg/KickAss.jar ./build.sh
#   ./build.sh run                  (bygg och starta i VICE, x64sc)
set -e
cd "$(dirname "$0")"

KICKASS="${KICKASS:-KickAss.jar}"
if [ ! -f "$KICKASS" ]; then
    echo "Hittar inte KickAss.jar. Ange sökvägen med KICKASS=/sökväg/KickAss.jar" >&2
    exit 1
fi

mkdir -p build
java -jar "$KICKASS" src/main.asm -o "$PWD/build/flighty64.prg"
echo "Klart: build/flighty64.prg"

if [ "$1" = "run" ]; then
    x64sc -autostart build/flighty64.prg
fi
