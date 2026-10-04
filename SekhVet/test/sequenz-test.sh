#!/bin/bash
# Paket CA: Unit-Test der Sequenz-Plaketten (28 Faelle aus ImagoPilot sequenz.test.ts).
# SekhVet Paket CS: plus negated/pre-contrast names, "T1+C", the CT phase rule of the overlay and the
# MR-only weighting badge. SEKHVET_TESTHAKEN=1 because subtraktionsName:minus: is test-only.
# Aufruf aus dem Repo-Wurzelordner: bash SekhVet/test/sequenz-test.sh
# SEKHVET_SEQUENZ_PNG=/pfad.png schreibt zusaetzlich eine Beispielminiatur mit Plaketten.
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/sekhvet-sequenz-test"
clang -fno-objc-arc -Wall -DSEKHVET_TESTHAKEN=1 -framework Cocoa -I Horos/Sources \
    Horos/Sources/SekhmetSequenz.m SekhVet/test/sequenz-test.m -o "$out"
"$out"
