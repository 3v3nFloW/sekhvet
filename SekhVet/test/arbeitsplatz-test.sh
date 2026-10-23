#!/bin/bash
# SekhVet Paket EE: unit test of monitor keys, workplaces and snapping (SekhmetArbeitsplatz.h).
# Call from the repository root: bash SekhVet/test/arbeitsplatz-test.sh
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/sekhvet-arbeitsplatz-test"
clang -fno-objc-arc -Wall -framework Foundation -I Horos/Sources SekhVet/test/arbeitsplatz-test.m -o "$out"
"$out"
