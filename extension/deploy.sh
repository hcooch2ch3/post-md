#!/bin/bash
# extension/deploy.sh: build, then deploy the output to the MarkEdit scripts directory
set -euo pipefail
cd "$(dirname "$0")"

CONTAINER="$HOME/Library/Containers/app.cyan.markedit/Data/Documents"
DEST="$CONTAINER/scripts"

# Check that MarkEdit is installed and initialized (gives a clear diagnostic instead of an opaque cp failure)
if [ ! -d "$CONTAINER" ]; then
  echo "error: MarkEdit is not installed/initialized ($CONTAINER missing)." >&2
  echo "       Launch MarkEdit once to create the container, then retry." >&2
  exit 1
fi

# Always build from the latest source (avoids deploying a stale artifact)
npm run build

mkdir -p "$DEST"
cp dist/post-md.js "$DEST/"
echo "deployed → $DEST/post-md.js (restart MarkEdit)"
