#!/usr/bin/env bash
# Packages an unsigned Lakhas.app into an .ipa for Sideloadly (ADR-012).
# The binaries are ad-hoc signed ("-": no certificate, no secret) only to embed the
# requested entitlements, so the re-signing tool can see that we ask for an App Group.
# Usage: build-ipa.sh <path/to/Lakhas.app> <output.ipa>
set -euo pipefail

APP="$1"
OUT="$2"
CONFIG_DIR="$(cd "$(dirname "$0")/../Config" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
BUNDLE="$WORK/Payload/$(basename "$APP")"

# Inner bundles first, then the app.
if [ -d "$BUNDLE/PlugIns" ]; then
  for appex in "$BUNDLE"/PlugIns/*.appex; do
    name="$(basename "$appex" .appex)"
    codesign --force --sign - --timestamp=none \
      --entitlements "$CONFIG_DIR/$name.entitlements" "$appex"
  done
fi
codesign --force --sign - --timestamp=none \
  --entitlements "$CONFIG_DIR/Lakhas.entitlements" "$BUNDLE"

# Verify each signed bundle really carries the App Group entitlement.
verify_entitlements() {
  local bundle="$1"
  local plist
  plist="$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)"
  echo "Entitlements of $(basename "$bundle"):"
  echo "$plist"
  if ! grep -q "com.apple.security.application-groups" <<<"$plist"; then
    echo "error: $(basename "$bundle") is missing the App Group entitlement" >&2
    exit 1
  fi
}
verify_entitlements "$BUNDLE"
if [ -d "$BUNDLE/PlugIns" ]; then
  for appex in "$BUNDLE"/PlugIns/*.appex; do verify_entitlements "$appex"; done
fi

# No secrets may ship in the IPA (PROJECT_PROMPT.md §3.1).
if grep -rIl --exclude='*.png' -e 'sk-ant-' -e 'BEGIN PRIVATE KEY' "$BUNDLE" >/dev/null 2>&1; then
  echo "error: secret-like string found in the app bundle" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$WORK" && zip -qry "$OUT_ABS" Payload)
echo "Wrote $OUT_ABS ($(du -h "$OUT_ABS" | cut -f1))"
