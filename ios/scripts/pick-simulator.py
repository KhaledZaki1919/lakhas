#!/usr/bin/env python3
"""Reads `xcrun simctl list devices available -j` from stdin and prints the UDID of an
iPhone simulator on the newest installed iOS runtime."""
import json
import re
import sys

devices = json.load(sys.stdin)["devices"]
best = None
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            if best is None or version > best[0]:
                best = (version, device["udid"], device["name"])
if best is None:
    sys.exit("No available iPhone simulator found")
print(f"Using {best[2]} (iOS {best[0][0]}.{best[0][1]})", file=sys.stderr)
print(best[1])
