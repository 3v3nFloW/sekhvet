#!/bin/zsh
# SekhVet — oeffentlichen Stand erzeugen (Entscheid 16.09.2026).
# Das private Repo bleibt Arbeitsrepo. Der Zweig "public" enthaelt die Horos-Historie und darauf
# je Release EINEN Commit "Kappa1-VRS GmbH" mit dem Baum von HEAD — ohne interne Commit-Nachrichten,
# ohne Personennamen, ohne ausgeschlossene Pfade.
#
# Aufruf: SekhVet/publish/oeffentlich-exportieren.sh ["Kurzbeschreibung des Releases"]
# Liste verbotener Begriffe (Personen-, Patienten-, Rechnernamen): ~/.sekhvet-verbotene-begriffe
# (eine Zeile je Begriff, erweiterter regulaerer Ausdruck) — liegt bewusst NICHT im Repo.
set -e
REPO=${REPO:-$HOME/Projects/horos-vet}
cd $REPO
LISTE=$HOME/.sekhvet-verbotene-begriffe
[[ -s $LISTE ]] || { echo "Begriffsliste $LISTE fehlt"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Arbeitsbaum nicht sauber - erst committen"; exit 1; }

PRIV=$(git rev-parse HEAD)
BASE=$(git merge-base HEAD origin/horos)
BUILD=$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' Horos/Horos.xcconfig)
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Horos/Info.plist 2>/dev/null || echo 1.0)
TEXT=${1:-"SekhVet $VER (build $BUILD)"}
AUSSCHLUSS=(Sachmet-Assets/Icon-Kandidaten)

WT=$(mktemp -d /tmp/sekhvet-public.XXXX)
if git rev-parse -q --verify refs/heads/public >/dev/null; then
  git worktree add -q $WT public
else
  git worktree add -q -b public $WT $BASE
fi
trap 'git -C $REPO worktree remove --force $WT >/dev/null 2>&1 || true' EXIT
cd $WT
git read-tree -u --reset $PRIV            # Baum des privaten Stands, samt Submodul-Zeigern
for p in $AUSSCHLUSS; do git rm -r -q --cached --ignore-unmatch -- $p; rm -rf -- $p; done

# Sperre: kein verbotener Begriff in den gegenueber Horos hinzugefuegten Zeilen oder Dateinamen
TREFFER=$(git diff --cached $BASE -U0 | grep '^[+]' | grep -v '^+++' | grep -n -E -f $LISTE || true)
NAMEN=$(git diff --cached $BASE --name-only | grep -E -f $LISTE || true)
if [[ -n $TREFFER || -n $NAMEN ]]; then
  echo "ABBRUCH - verbotene Begriffe:"; echo $TREFFER | cut -c1-160 | head -20; echo $NAMEN
  exit 1
fi

if git diff --cached --quiet; then echo "public ist schon auf diesem Stand"; exit 0; fi
GIT_AUTHOR_NAME="Kappa1-VRS GmbH" GIT_AUTHOR_EMAIL="sekhvet@kappa1.vet" \
GIT_COMMITTER_NAME="Kappa1-VRS GmbH" GIT_COMMITTER_EMAIL="sekhvet@kappa1.vet" \
  git commit -q -m "$TEXT" -m "Veterinary fork of Horos (LGPL-3.0). Source of SekhVet $VER build $BUILD."
echo "public: $(git log --oneline -1)  (Basis Horos ${BASE[1,9]}, privat ${PRIV[1,9]})"
git diff --stat $BASE HEAD | tail -1
