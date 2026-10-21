#!/usr/bin/env bash
# One-command install of the latest Surge Pricing release.
#
#   curl -fsSL https://raw.githubusercontent.com/ahab94/surge-pricing/main/install.sh | bash
#
# macOS: installs "Surge Pricing.app" into ~/Applications and opens it.
# Linux: installs into ~/.local/share/surge-pricing, adds the
#        `surge-pricing` command and a desktop menu entry.
# Overrides: INSTALL_DIR=..., BIN_DIR=... (Linux), NO_LAUNCH=1 to skip starting it.
# Uninstall: run it again with UNINSTALL=1.
set -euo pipefail

REPO="ahab94/surge-pricing"
NAME="Surge Pricing"
SLUG="surge-pricing"
WEB="https://ahab94.github.io/$SLUG/"

case "$(uname -s)" in
	Darwin) platform=macos ;;
	Linux) platform=linux ;;
	*) echo "This installer is for macOS and Linux. On Windows use install.ps1, or play in your browser: $WEB"; exit 1 ;;
esac
if [ "$platform" = linux ] && [ "$(uname -m)" != x86_64 ]; then
	echo "Linux builds are x86_64 only. Play in your browser instead: $WEB"
	exit 1
fi

if [ "$platform" = macos ]; then
	dest="${INSTALL_DIR:-$HOME/Applications}"
	app="$dest/$NAME.app"
else
	dest="${INSTALL_DIR:-$HOME/.local/share/$SLUG}"
	bin="${BIN_DIR:-$HOME/.local/bin}"
	desktop="$HOME/.local/share/applications/$SLUG.desktop"
fi

if [ -n "${UNINSTALL:-}" ]; then
	if [ "$platform" = macos ]; then rm -rf "$app"; else rm -rf "$dest" "$bin/$SLUG" "$desktop"; fi
	echo "$NAME uninstalled. (Saved progress is kept in Godot's user data folder.)"
	exit 0
fi

for tool in curl unzip; do
	command -v "$tool" >/dev/null || { echo "Please install '$tool' first."; exit 1; }
done

echo "Finding the latest release..."
url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -o "https://[^\"]*-$platform\.zip" | head -1 || true)
[ -n "$url" ] || { echo "Couldn't find a $platform build in the latest release. See https://github.com/$REPO/releases"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading ${url##*/}..."
curl -fL --progress-bar -o "$tmp/game.zip" "$url"
# Verify the download against the release's published SHA-256 sums; refuse to
# install anything that doesn't match (corrupted or tampered download).
curl -fsSL -o "$tmp/SHA256SUMS" "${url%/*}/SHA256SUMS" || { echo "Couldn't fetch SHA256SUMS for this release; not installing."; exit 1; }
want=$(grep " ${url##*/}\$" "$tmp/SHA256SUMS" | cut -d' ' -f1)
if command -v sha256sum >/dev/null; then got=$(sha256sum "$tmp/game.zip" | cut -d' ' -f1); else got=$(shasum -a 256 "$tmp/game.zip" | cut -d' ' -f1); fi
[ -n "$want" ] && [ "$want" = "$got" ] || { echo "Checksum mismatch for ${url##*/}; not installing."; exit 1; }
echo "Checksum OK."
unzip -q "$tmp/game.zip" -d "$tmp/game"

if [ "$platform" = macos ]; then
	mkdir -p "$dest"
	rm -rf "$app"
	mv "$tmp/game/$NAME.app" "$dest/"
	# The app is ad-hoc signed, not notarized; clear the quarantine flag so it opens normally.
	xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
	echo "Installed: $app"
	[ -n "${NO_LAUNCH:-}" ] || open "$app"
else
	rm -rf "$dest"
	mkdir -p "$dest" "$bin" "$(dirname "$desktop")"
	cp -R "$tmp/game/." "$dest/"
	chmod +x "$dest/SurgePricing.x86_64"
	curl -fsSL -o "$dest/icon.svg" "https://raw.githubusercontent.com/$REPO/main/icon.svg" || true
	ln -sf "$dest/SurgePricing.x86_64" "$bin/$SLUG"
	cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Arcade rideshare chaos: your rating is your health bar
Exec=$dest/SurgePricing.x86_64
Icon=$dest/icon.svg
Categories=Game;
EOF
	echo "Installed: $dest"
	echo "Run it with: $SLUG   (or find \"$NAME\" in your app menu)"
	case ":$PATH:" in *":$bin:"*) ;; *) echo "Note: $bin isn't on your PATH yet." ;; esac
	[ -n "${NO_LAUNCH:-}" ] || ("$dest/SurgePricing.x86_64" >/dev/null 2>&1 &)
fi
