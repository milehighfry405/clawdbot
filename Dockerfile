# Build openclaw from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:22-bookworm AS openclaw-build

# Dependencies needed for openclaw build
RUN apt-get update \
&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
git \
ca-certificates \
curl \
python3 \
make \
g++ \
&& rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known-good ref (tag/branch). Override in Railway template settings if needed.
# Using a released tag avoids build breakage when `main` temporarily references unpublished packages.
ARG OPENCLAW_GIT_REF=v2026.5.3-1
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch: relax version requirements for packages that may reference unpublished versions.
# Apply to all extension package.json files to handle workspace protocol (workspace:*).
RUN set -eux; \
find ./extensions -name 'package.json' -type f | while read -r f; do \
sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
ca-certificates \
tini \
python3 \
python3-venv \
curl \
git \
&& rm -rf /var/lib/apt/lists/*

# Install Bun in runtime too, because we need it for gbrain
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# `openclaw update` expects pnpm. Provide it in the runtime image.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Persist user-installed tools by default by targeting the Railway volume.
# - npm global installs -> /data/npm
# - pnpm global installs -> /data/pnpm (binaries) + /data/pnpm-store (store)
ENV NPM_CONFIG_PREFIX=/data/npm
ENV NPM_CONFIG_CACHE=/data/npm-cache
ENV PNPM_HOME=/data/pnpm
ENV PNPM_STORE_DIR=/data/pnpm-store
ENV PATH="/data/npm/bin:/data/pnpm:/root/.bun/bin:${PATH}"

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Install gbrain in runtime. Pin to a known-good commit; override in Railway template settings if needed.
ARG GBRAIN_GIT_REF=9e2093f
RUN git clone https://github.com/garrytan/gbrain.git /root/gbrain \
&& cd /root/gbrain \
&& git checkout "${GBRAIN_GIT_REF}" \
&& chmod +x src/cli.ts \
&& bun install \
&& bun link

# Provide an openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
&& chmod +x /usr/local/bin/openclaw

COPY src ./src

# Default AGENTS.md + TOOLS.md templates seeded into /data/workspace/ on first
# boot if absent. AGENTS.md is the OpenClaw operating-protocol convention;
# TOOLS.md documents gbrain + other available tools for the agent.
COPY templates/AGENTS.md /app/templates/AGENTS.md
COPY templates/TOOLS.md /app/templates/TOOLS.md

# Create startup script inline
RUN mkdir -p /app/docker && cat > /app/docker/start-with-gbrain.sh <<'EOF'
#!/usr/bin/env bash
set -e

export PATH="/data/npm/bin:/data/pnpm:/root/.bun/bin:$PATH"

# Seed AGENTS.md + TOOLS.md into the workspace volume on first boot. Each is
# only copied if absent, so user edits persist across redeploys.
if [ -d /data/workspace ]; then
if [ ! -f /data/workspace/AGENTS.md ] && [ -f /app/templates/AGENTS.md ]; then
cp /app/templates/AGENTS.md /data/workspace/AGENTS.md
fi
if [ ! -f /data/workspace/TOOLS.md ] && [ -f /app/templates/TOOLS.md ]; then
cp /app/templates/TOOLS.md /data/workspace/TOOLS.md
fi
# Copy the gbrain skill resolver into the workspace so AGENTS.md routing
# can fall back to the full dispatch table for skills not inlined above.
# `gbrain skillpack install --all` does NOT copy RESOLVER.md (only individual
# SKILL.md files), so we copy it here.
mkdir -p /data/workspace/skills
if [ ! -f /data/workspace/skills/RESOLVER.md ] && [ -f /root/gbrain/skills/RESOLVER.md ]; then
cp /root/gbrain/skills/RESOLVER.md /data/workspace/skills/RESOLVER.md
fi
fi

# Clone the brain repo on first boot if the env vars are configured.
# GBRAIN_BRAIN_REPO_URL: e.g. github.com/owner/repo (no scheme)
# GITHUB_TOKEN: PAT with read access (private repos only)
if [ -n "${GBRAIN_BRAIN_REPO_URL:-}" ] && [ ! -d /data/brain-repo/.git ]; then
mkdir -p /data
if [ -n "${GITHUB_TOKEN:-}" ]; then
git clone "https://${GITHUB_TOKEN}@${GBRAIN_BRAIN_REPO_URL#https://}" /data/brain-repo || true
else
git clone "https://${GBRAIN_BRAIN_REPO_URL#https://}" /data/brain-repo || true
fi
fi

if command -v gbrain >/dev/null 2>&1; then
gbrain apply-migrations --yes || true

# Install autopilot pinned to the brain repo if present, else DB-only maintenance.
if [ -d /data/brain-repo/.git ]; then
gbrain autopilot --install --repo /data/brain-repo || true
else
gbrain autopilot --install || true
fi

if [ -f /root/.gbrain/start-autopilot.sh ]; then
bash /root/.gbrain/start-autopilot.sh &
fi
fi

exec node src/server.js
EOF

RUN chmod +x /app/docker/start-with-gbrain.sh

# The wrapper listens on $PORT.
# IMPORTANT: Do not set a default PORT here.
# Railway injects PORT at runtime and routes traffic to that port.
# If we force a different port, deployments can come up but the domain will route elsewhere.
EXPOSE 8080

# Ensure PID 1 reaps zombies and forwards signals.
ENTRYPOINT ["tini", "--"]
CMD ["bash", "/app/docker/start-with-gbrain.sh"]
