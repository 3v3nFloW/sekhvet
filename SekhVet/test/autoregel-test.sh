#!/bin/bash
# SekhVet Paket ED: unit test of the automatic-retrieve rule (SekhmetAutoRegel.h).
# Call from the repository root: bash SekhVet/test/autoregel-test.sh
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/sekhvet-autoregel-test"
clang -fno-objc-arc -Wall -framework Foundation -I Horos/Sources SekhVet/test/autoregel-test.m -o "$out"
"$out"
