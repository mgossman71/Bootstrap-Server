#!/bin/sh
set -e

# Write runtime configs to the writable volume (not the read-only html dir)
CONFIG_DIR="/usr/share/nginx/html-config"
mkdir -p "$CONFIG_DIR"

# Server config: public URL for dashboard commands
if [ -n "$BOOTSTRAP_PUBLIC_URL" ]; then
    echo "{\"public_url\":\"${BOOTSTRAP_PUBLIC_URL}\"}" > "$CONFIG_DIR/server-config.json"
else
    echo "{\"public_url\":\"\"}" > "$CONFIG_DIR/server-config.json"
fi

# Build info: copy from image (baked at build time) to writable dir
if [ -f "/etc/bootstrap/build-info.json" ]; then
    cp /etc/bootstrap/build-info.json "$CONFIG_DIR/build-info.json"
else
    echo "{\"git_sha\":\"unknown\",\"git_branch\":\"unknown\",\"build_time\":\"unknown\"}" > "$CONFIG_DIR/build-info.json"
fi

# Hand off to nginx
exec nginx -g 'daemon off;'
