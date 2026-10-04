#!/bin/bash
# Paket CB: Unit-Test der Update-Pruefung (Angebotswahl + Build-Nummer).
# Aufruf aus dem Repo-Wurzelordner: bash SekhVet/test/update-test.sh
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/sekhvet-update-test"
clang -fno-objc-arc -Wall -framework Cocoa -I Horos/Sources \
    Horos/Sources/SekhmetUpdate.m SekhVet/test/update-test.m -o "$out"
"$out" SekhVet/test/update-github-2026-09-27.json
