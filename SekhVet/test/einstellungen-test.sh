#!/bin/bash
# SekhVet Paket DZ: unit test of the settings groups, the blocked keys, the take-over and the file check.
# Call from the repository root: bash SekhVet/test/einstellungen-test.sh
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/sekhvet-einstellungen-test"
clang -fno-objc-arc -Wall -DSEKHVET_LOGIC_TEST=1 -framework Foundation -I Horos/Sources \
    Horos/Sources/SekhmetEinstellungen.m SekhVet/test/einstellungen-test.m -o "$out"
"$out"
