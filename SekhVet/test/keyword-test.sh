#!/bin/bash
# Paket CS: unit test of the hanging-protocol keyword matching (SekhmetOrientation.m) and of the contrast detection
# of the opening protocols (SekhmetOpening.m). Both files carry their pure Foundation logic above
# "#ifndef SEKHVET_LOGIC_TEST"; this test compiles exactly that code, without the application classes.
# Call from the repository root: bash SekhVet/test/keyword-test.sh
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/sekhvet-keyword-test"
clang -fno-objc-arc -Wall -DSEKHVET_LOGIC_TEST=1 -framework Cocoa -I Horos/Sources \
    SekhVet/test/keyword-test.m -o "$out"
"$out"
