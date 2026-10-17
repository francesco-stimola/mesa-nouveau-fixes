#!/bin/sh
# Let Firefox decode video in hardware on nouveau. Firefox blocks VA-API on
# NVIDIA GPUs unless media.hardware-video-decoding.force-enabled is true.
# This sets it as the default for every profile through the system policy
# file, /etc/firefox/policies/policies.json, keeping any policies already
# there.
#
# Usage: ./scripts/setup-firefox.sh   (uses sudo to write the policy file)
set -eu

policy=/etc/firefox/policies/policies.json
pref=media.hardware-video-decoding.force-enabled

command -v python3 > /dev/null || {
	echo "setup-firefox: python3 is required" >&2
	exit 1
}

if command -v snap > /dev/null && snap list firefox > /dev/null 2>&1; then
	echo "Note: Firefox is installed as a Snap. A Snap brings its own Mesa and"
	echo "ignores the system one: install Mozilla's .deb, see docs/SETUP.md."
fi
if command -v flatpak > /dev/null && flatpak info org.mozilla.firefox > /dev/null 2>&1; then
	echo "Note: Firefox is installed as a Flatpak. A Flatpak brings its own Mesa"
	echo "and ignores the system one: install Mozilla's .deb, see docs/SETUP.md."
fi

sudo mkdir -p "$(dirname "$policy")"
sudo python3 - "$policy" "$pref" << 'EOF'
import json
import os
import sys

path, pref = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
prefs = data.setdefault("policies", {}).setdefault("Preferences", {})
prefs[pref] = {"Value": True, "Status": "default"}
with open(path + ".new", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.chmod(path + ".new", 0o644)
os.replace(path + ".new", path)
print(f"{path}: {pref} is now true by default")
EOF
echo "Restart Firefox, then check about:policies."
