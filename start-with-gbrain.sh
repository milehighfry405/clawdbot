#!/usr/bin/env bash
set -e

export PATH="/root/.bun/bin:$PATH"

if command -v gbrain >/dev/null 2>&1; then
gbrain apply-migrations --yes || true
gbrain autopilot --install || true

if [ -f /root/.gbrain/start-autopilot.sh ]; then
bash /root/.gbrain/start-autopilot.sh &
fi
fi

exec node src/server.js
