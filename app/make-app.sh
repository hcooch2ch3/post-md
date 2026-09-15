#!/bin/bash
# app/make-app.sh: swift build → assemble .app → register with Launch Services → run
set -euo pipefail
cd "$(dirname "$0")"
# i18n acceptance gate: fail fast if Korean UI/data drifted from the allowlist (before the slow build).
bash "$(git rev-parse --show-toplevel)/scripts/i18n-guard.sh"
swift build -c release
APP="build/post-md.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/PostMD" "$APP/Contents/MacOS/PostMD"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
# Kill any running instance. If one is already running, `open` just activates the
# existing (old) process instead of relaunching it, so without this you'd see the old
# UI rather than the new build.
pkill -x PostMD 2>/dev/null || true
sleep 0.3
open "$APP"
