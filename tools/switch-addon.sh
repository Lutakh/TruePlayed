#!/bin/bash
# Switches the TruePlayed add-on of the game between the CurseForge install and a
# development copy of this repository (docs/PUBLISHING-fr.md, step 3).
#
#   tools/switch-addon.sh dev         copy the repository into AddOns/TruePlayed (run it
#                                     again after every change); the CurseForge folder
#                                     is set aside first
#   tools/switch-addon.sh curseforge  remove the development copy and put the CurseForge
#                                     folder back
#   tools/switch-addon.sh status      which version the game loads
#
# The development copy is a copy, not a symbolic link: what the CurseForge app or a
# launcher writes into the add-on folder never reaches the repository. It holds a
# .truePlayed-dev marker and its TOC version reads dev-<commit> (a "+" when the working
# tree has changes). The CurseForge folder is set aside as Interface/TruePlayed.curseforge,
# outside AddOns, where neither the game nor the CurseForge app look. Quit the game
# first: it reads add-on files only at start. TP_GAME overrides the game folder.
set -eu

GAME=${TP_GAME:-"/Applications/World of Warcraft/_classic_beta_"}
ADDONS="$GAME/Interface/AddOns"
DEST="$ADDONS/TruePlayed"
STASH="$GAME/Interface/TruePlayed.curseforge"
MARKER=".truePlayed-dev"
REPO=$(cd "$(dirname "$0")/.." && pwd)

die() { echo "switch-addon: $*" >&2; exit 1; }

# none, link (an older symbolic link to the repository), dev, or curseforge (any other
# real folder: the CurseForge app's install or an unzipped package)
mode() {
  if [ -L "$DEST" ]; then echo link
  elif [ ! -e "$DEST" ]; then echo none
  elif [ -f "$DEST/$MARKER" ]; then echo dev
  else echo curseforge
  fi
}

check_game() {
  [ -d "$ADDONS" ] || die "no AddOns folder: $ADDONS (set TP_GAME)"
  if pgrep -f "$GAME/.*\.app/Contents/MacOS/" >/dev/null 2>&1; then
    die "quit the game first (it reads add-on files only at start)"
  fi
}

version_of() {
  sed -n 's/^## Version: *//p' "$1/TruePlayed.toc" 2>/dev/null | head -n 1
}

to_dev() {
  check_game
  case $(mode) in
    link) rm "$DEST" ;;   # the link only, never the repository it points to
    curseforge)
      [ -e "$STASH" ] && die "both $DEST and $STASH exist: keep one, remove the other"
      mv "$DEST" "$STASH"
      echo "CurseForge version set aside: $STASH" ;;
  esac
  mkdir -p "$DEST"
  # The files of the package (.pkgmeta ignores the same folders); dotfiles stay out, and
  # the marker, excluded too, survives --delete.
  rsync -a --delete --exclude '.*' --exclude /tests --exclude /docs --exclude /design \
    --exclude /tools --exclude /media-src --exclude /RELEASE_NOTES.md "$REPO/" "$DEST/"
  local ver
  ver="dev-$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo local)"
  if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then ver="$ver+"; fi
  for toc in "$DEST"/*.toc; do sed -i '' "s/@project-version@/$ver/" "$toc"; done
  echo "$ver" > "$DEST/$MARKER"
  echo "Development copy $ver in $DEST"
}

to_curseforge() {
  check_game
  case $(mode) in
    dev) rm -rf "$DEST" ;;   # a copy made by to_dev (marker checked by mode)
    link) rm "$DEST" ;;
    curseforge)
      [ -e "$STASH" ] && die "both $DEST and $STASH exist: keep one, remove the other" ;;
  esac
  if [ -e "$STASH" ]; then
    mv "$STASH" "$DEST"
    echo "CurseForge version $(version_of "$DEST") back in $DEST"
    echo "Open the CurseForge app: it updates TruePlayed if a newer version is out."
  elif [ -e "$DEST" ]; then
    echo "Already on the CurseForge version $(version_of "$DEST")"
  else
    echo "No CurseForge version set aside: install TruePlayed from the CurseForge app."
  fi
}

status() {
  case $(mode) in
    none) echo "No TruePlayed in $ADDONS" ;;
    link) echo "Symbolic link to $(readlink "$DEST") (older setup: run dev to replace it)" ;;
    dev) echo "Development copy $(cat "$DEST/$MARKER")" ;;
    curseforge) echo "CurseForge version $(version_of "$DEST")" ;;
  esac
  if [ -e "$STASH" ]; then echo "Set aside: CurseForge version $(version_of "$STASH")"; fi
}

case "${1:-status}" in
  dev) to_dev ;;
  curseforge|cf) to_curseforge ;;
  status) status ;;
  *) die "usage: $0 dev | curseforge | status" ;;
esac
