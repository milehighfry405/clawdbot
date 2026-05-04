# Tools available to OpenClaw

## gbrain — your shared brain

**What it is:** a Postgres-backed knowledge brain holding everything Ben has captured: BenOS vault notes, gstack session learnings, people, companies, decisions, original thinking. Hybrid search (vector + keyword). Same DB as Ben's Mac.

**You should query gbrain before answering anything that might already be in it.** Don't paraphrase from your training data when the brain has the actual content.

### Commands you'll use most

| Command | When |
|---|---|
| `gbrain search "<keyword>"` | Fast keyword match. Use first when looking for a known term, name, or slug. |
| `gbrain query "<natural question>"` | Hybrid retrieval (vector + keyword). Use for fuzzy questions like "what does Ben think about X". |
| `gbrain get <slug>` | Read a specific page once you know its slug (e.g. `gbrain get people/alice`). |
| `gbrain get-backlinks <slug>` | See what other pages link here. Useful for finding context around an entity. |
| `gbrain put-page <slug>` | Write/update a page. Auto-extracts links from the body — you don't need to run `gbrain link`. |
| `gbrain list-pages --type concept` | Browse by type. Types in this brain: reference, concept, project, decision, meeting, daily, archive, debrief. |
| `gbrain stats` | Page count, embedding count, source breakdown. Sanity check. |
| `gbrain doctor` | Health check (orphan pages, missing embeddings, broken citations). `gbrain doctor --fix` to repair. |
| `gbrain --help` | Full command list. |

### "Do a gbrain poll" — what it means

When Ben says **"do a gbrain poll"** or **"poll the brain"**, run this sequence before answering:

1. `gbrain search` for any names/keywords from his message
2. `gbrain query` for the gist of his question
3. Read the top 3–5 hits with `gbrain get`
4. Cite slugs in your reply (`see [decisions/foo](decisions/foo)`) so he can navigate

If results are thin, say so explicitly — don't pad with your own knowledge.

### How content gets into the brain

Two paths feed the same Supabase DB. Don't fight them.

- **gstack content** → Ben works on his Mac → gstack writes md → push to `milehighfry405/gstack-brain-ben` on GitHub → this container's autopilot pulls every cycle → ingested. Slugs like `projects/*`, `builder-journey`, `originals/*`, `concepts/*`, `ideas/*`.
- **BenOS vault** → Ben commits in `~/Desktop/BenOS/` on his Mac → post-commit hook calls `gbrain put-page` directly to Supabase. Slugs like `benos/*`.

### Slug discipline (don't break this)

- **Never write a `benos/*` slug from this agent.** That namespace is owned by the Mac post-commit hook. Anything you put there will be overwritten on Ben's next BenOS commit.
- Vault-shaped insights you want to capture → write to `concepts/<slug>`, `originals/<slug>`, or `ideas/<slug>`. Ben can hand-promote into BenOS later if he wants.
- gstack-side slugs (`projects/*`, etc.) are fair game for you to write/update.

### Don't-do rules

- Don't run `gbrain autopilot` or `gbrain sync` manually — autopilot is already running with `--repo /data/brain-repo` and pulls every cycle. Manual runs cause lockfile conflicts.
- Don't run `gbrain purge` or `gbrain drop` without an explicit user instruction naming the action and target.
- Don't write a slug under a directory you've never written before without confirming with Ben first.
- Don't paraphrase brain content into a long answer if the brain page already says it concisely — quote and cite.

## clawvisor — your Google credential gateway

ClawVisor is the MCP tool that grants OpenClaw scoped access to the user's
Google account (Gmail + Calendar). It's loaded as a runtime MCP server, so
you have it available as a tool — but you need to KNOW to use it, not wait
for the user to remind you.

### Gmail (via clawvisor)

| User says | What you do |
|---|---|
| "Did X email me?", "search inbox for X" | Use clawvisor Gmail search. |
| "Draft a reply to X", "draft an email about Y" | Use clawvisor to create a Gmail **draft**. Show the body, never auto-send. |
| "What's the latest from X?" | Search inbox, summarize, link to thread. |

**Critical: Gmail OAuth scope is `gmail.readonly` + drafts. You CANNOT send.**
Every outbound email goes to Drafts for the user to review and send manually.
This is policy enforced at the agent layer, not by OAuth scope. Do not bypass.

### Calendar (via clawvisor)

| User says | What you do |
|---|---|
| "What's on my calendar today?" | Use clawvisor calendar read. |
| "Am I free at 2pm?", "next meeting?" | Use clawvisor calendar read. |
| "Schedule X" | NOT supported — calendar is read-only. Tell the user to do it manually. |

If clawvisor returns auth errors, the OAuth token may need refresh. Tell
the user; don't try to re-auth silently.

## openclaw — the gateway you live in

The OpenClaw runtime is your host. Its dashboard, tools, and conventions are
documented in `AGENTS.md` (which sits next to this file in `/data/workspace/`).
Read both.

## Other tools

- **Telegram** — the user pings you here. You send replies via the OpenClaw gateway, not by direct API calls.
- **cron** — register scheduled jobs (e.g. nightly dream cycle at 2am quiet hours).
- **subagents / sessions_spawn** — fork sub-agents for parallel signal capture.

## Versioning

- gbrain is pinned in this image. Check with `gbrain --version`. Ben's Mac client should match (or be within one minor). If they drift, flag it.
- This file (`TOOLS.md`) and `AGENTS.md` are seeded from baked-in templates on first boot of a fresh volume. Edits you make to either persist on the Railway volume across redeploys.
