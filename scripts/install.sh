#!/bin/bash
# Install Pluto for Mac into /Applications and start it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d out/Pluto.app ]; then
    ./scripts/build.sh
fi

# Stop a running Pluto, if any.
pkill -x Pluto 2>/dev/null || true
sleep 0.5

echo "▸ Installing to /Applications…"
rm -rf /Applications/Pluto.app
ditto out/Pluto.app /Applications/Pluto.app

# Extend quarantine removal in case the file came from a download.
xattr -dr com.apple.quarantine /Applications/Pluto.app 2>/dev/null || true

echo "▸ Launching Pluto…"
open /Applications/Pluto.app

echo "✓ Pluto is installed. The notch bot lives at the top of your screen;"
echo "  find it in the menu bar (🪐) for Settings and to quit."
