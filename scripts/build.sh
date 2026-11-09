#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Gather git metadata
GIT_SHA=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Building bootstrap-server"
echo "  Git: ${GIT_BRANCH}@${GIT_SHA}"
echo "  Time: ${BUILD_TIME}"

# Generate playbooks index for the API
node -e "
const fs = require('fs');
const path = require('path');
const playbooksDir = path.join('${PROJECT_DIR}', 'serve', 'playbooks');
const playbooks = fs.readdirSync(playbooksDir).filter(f => f.endsWith('.yml'));
const index = { playbooks };
fs.writeFileSync(path.join(playbooksDir, '..', 'playbooks-index.json'), JSON.stringify(index, null, 2));
" 2>/dev/null || \
python3 -c "
import json, os
pdir = '${PROJECT_DIR}/serve/playbooks'
pbs = sorted([f for f in os.listdir(pdir) if f.endswith('.yml')])
with open(os.path.join(pdir, '..', 'playbooks-index.json'), 'w') as fh:
    json.dump({'playbooks': pbs}, fh, indent=2)
"

docker build \
    --build-arg GIT_SHA="$GIT_SHA" \
    --build-arg GIT_BRANCH="$GIT_BRANCH" \
    --build-arg BUILD_TIME="$BUILD_TIME" \
    -t bootstrap-server:latest \
    -t "bootstrap-server:${GIT_SHA}" \
    "$PROJECT_DIR"

echo "✓ Built: bootstrap-server:latest (${GIT_SHA})"
