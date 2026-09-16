# dasik-aur — Agent Guide

The Arch package (`PKGBUILD`) for [dasik](https://github.com/amt911/dasik), a declarative Arch
Linux installer, plus `iso-bootstrap.sh`, the script that gets dasik onto a live ISO in one command.

## Start here

- **This repo is packaging, not the product.** `dasik` itself (the Python installer) lives
  upstream at `amt911/dasik`; this repo only builds and ships it as an Arch package and bootstraps
  it onto a live ISO. There is no application source here to design, test or refactor.
- **Read `README.md` first** — it documents the install paths (ISO bootstrap, existing-system
  `makepkg -si`), the private-config-repo convention, and the release flow. This guide only adds
  agent-specific process on top of it.
- **Cutting a release is the one recurring task**: `scripts/bump.sh <pkgver> [pkgrel] [--push]`
  (see [Commands](#commands)). It is the only script that should ever edit `pkgver`/`pkgrel` in
  `PKGBUILD` or regenerate `.SRCINFO`.

## Agent compatibility — Codex and Claude Code

This file is `AGENTS.md`: the **one** instruction file for every coding agent in this repo. Codex
reads it directly; Claude Code reads `CLAUDE.md`, which only imports this file (`@AGENTS.md`) and
holds what applies to Claude alone. **Edit rules here, never in `CLAUDE.md`** — two copies of a
rule drift apart on the first edit, and each agent then obeys a different one.

| Concern | Claude Code | Codex |
| --- | --- | --- |
| Instruction file | `CLAUDE.md` → imports `AGENTS.md` | `AGENTS.md` (root down to the working directory) |
| Invoke a skill | `Skill` tool, or `/<skill>` | mention it (`$<skill>`), or let it trigger from its description |
| Skills on disk | `~/.claude/skills` (links into `~/.agents/skills`) | `.agents/skills`, then `~/.agents/skills` |
| superpowers | `superpowers@claude-plugins-official` (`/plugin install`) | `superpowers@openai-curated` (install from `/plugins`; that id is its key in `~/.codex/config.toml`) |
| MCP servers | `claude mcp add -s user <name> -- <cmd>` | `codex mcp add <name> -- <cmd>` (`~/.codex/config.toml`) |
| File size | imports load whole | `project_doc_max_bytes`, **32 KiB by default** — raise it when this file is bigger, or the tail is silently dropped |

- **Install shared skills once, for both agents:** `npx skills add <owner/repo> -g --skill <name>`
  writes to `~/.agents/skills` and links it for Claude Code, so both run the same version.
- **Names in this file are capabilities, not one agent's syntax.** "Invoke the `X` skill" means the
  `Skill` tool in Claude Code and a skill mention in Codex. An MCP server named here is used when it
  is registered for the agent you are running in; its absence never blocks ordinary work.
- **Modes, model caps and Git rules bind both agents.** "lite mode", "normal mode" and "modo
  desatendido" mean the same in Codex; a cap written as "no model above Sonnet" means "no model
  above the mid tier" there.
- **Claude-only commands** (slash commands that are not skills) are skipped by Codex unless the
  same capability is installed as a skill in `~/.agents/skills`.

## ⚡ superpowers — use whenever applicable

Always prefer **superpowers** skills over ad-hoc approaches. If there's even a small chance a
skill applies to the task, invoke it via the `Skill` tool before acting (including before
clarifying questions).

- **Process skills first** — `brainstorming` before creative/feature work, `systematic-debugging`
  before fixing bugs, `test-driven-development` before writing implementation.
- **Then implementation skills** — domain-specific skills guide execution.
- **Verify before claiming done** — `verification-before-completion` / `requesting-code-review`
  before merging.

User instructions always take precedence over skills; skills override default behavior. **Skills
refine *how* the work is done; they never override the rules in this file. When a skill and this
`AGENTS.md` conflict, this file wins.**

### Mode switch

- **"lite mode"** — fully disables superpowers: no skill is invoked, not even the applicability
  check, until **"normal mode"** is said.
- **"normal mode"** (default) — standard superpowers behavior, plus: when delegating coding work,
  dispatch at most 1 agent at a time, and never use a model above Sonnet (no Opus). The cap counts
  **implementation** agents; a read-only review agent may run alongside one.
- **"modo desatendido"** (unattended mode) — the user is away and delegates autonomy: work without
  waiting for confirmations and make reasonable decisions yourself instead of asking. In this mode
  you MAY **`git push` the feature branches you create** and **open PRs via `gh`** on your own, so
  the work is ready for review when the user returns. The hard limits still hold and are NOT
  lifted: **never merge anything** (no `git merge`, no fast-forward integration, no `gh pr merge`),
  **never push to `main`** or any protected/default branch directly, and **never**
  `git push --force` / `--force-with-lease`. Deliver everything as pushed branches + PRs for the
  user to merge. Reverts to defaults on **"normal mode"**.

Confirm the switch briefly when it happens.

## Stack

| Tech | Role |
| --- | --- |
| `PKGBUILD` / `makepkg` | Arch packaging — builds `dasik` from the upstream Git tag |
| Bash | `iso-bootstrap.sh` (ISO bootstrap) and `scripts/bump.sh` (release cutting) |
| GitHub Actions (`archlinux:base-devel` container) | CI: `makepkg`, `namcap`, a package smoke test, and release publishing on tag push |
| `namcap` | Advisory packaging-lint, run in CI only |

## Layout

```text
/
├── PKGBUILD                     # pkgname=dasik; source pinned to the upstream git tag; build/check/package()
├── .SRCINFO                     # generated by `makepkg --printsrcinfo` — never hand-edit; scripts/bump.sh regenerates it
├── iso-bootstrap.sh              # installs dasik + gh device-code login + clones the private config repo, on a live ISO
├── scripts/bump.sh               # the only thing that edits pkgver/pkgrel and tags a release
├── .github/workflows/build.yml   # makepkg → namcap → smoke test → (on tag) `gh release create`
└── README.md                     # install paths, private-config-repo convention, release flow
```

## Commands

Every command below exists in this repo today (`scripts/bump.sh`, `.github/workflows/build.yml`,
`iso-bootstrap.sh`) — don't add one that doesn't.

```bash
# Build and install locally (existing Arch system)
makepkg -si

# Cut a release: bumps pkgver/pkgrel in PKGBUILD, regenerates .SRCINFO, commits, tags
scripts/bump.sh 0.2.0            # pkgrel defaults to 1
scripts/bump.sh 0.2.0 2          # explicit pkgrel
scripts/bump.sh 0.2.0 --push     # ...and push main + the tag (triggers the release build)

# What CI runs on every push/PR (archlinux:base-devel container, unprivileged builder user)
sudo -u builder makepkg --syncdeps --noconfirm --cleanbuild
namcap PKGBUILD ./*.pkg.tar.zst                 # advisory
pacman -U --noconfirm ./*.pkg.tar.zst           # smoke test: install the built package…
dasik --version
dasik --help
python -m dasik --help                          # …exercise the entry point both ways…
dasik check /usr/share/dasik/examples/install-simple.json   # …and validate a shipped sample

# Bootstrap dasik onto a live Arch ISO (what a user runs, not CI)
bash iso-bootstrap.sh --config-repo owner/name --dest /path [--no-clone] [--build]
```

There is no local dev server, no test suite and no lint config of its own to run here — `namcap`
(CI-only, advisory) and the CI smoke test above are the whole verification surface.

## Working rules

- **SOLID and the UI/UX workflow do not apply here** — this is pure AUR packaging plus a bootstrap
  shell script, no application code of its own (the installer lives upstream, `amt911/dasik`).
  Decided and written down.
- **No coverage or mutation gate** — there is no executable code or test suite here to cover or
  mutate; CI's `check()` step only compiles the upstream source (`python -m compileall`), and the
  real test/mutation gates live in the upstream repo's own CI. The smoke test in `build.yml`
  (`pacman -U`, `dasik --help`, `dasik check`) is a packaging sanity check, not a test suite.
- **`scripts/bump.sh` is the only thing that edits `pkgver`, `pkgrel` or `.SRCINFO`.** Never
  hand-edit those — a hand edit skips the upstream-tag-exists check and can publish a release that
  fails at `git checkout`.
- **New `depends`/`optdepends`/`makedepends`: ask first.** State which package, why, and whether
  it's hard or optional (the comment above `optdepends` in `PKGBUILD` already explains the
  reasoning for the existing ones) before adding another.
- **Commits in English**, Conventional Commits.

## Git & GitHub

- **Commits and branches OK** — create commits and new branches whenever it makes sense, without
  asking first.
- **Never push** *(default)* — no `git push` under any circumstance, and absolutely never
  `git push --force` / `--force-with-lease`. Leave pushing to the user. **Exception:** when
  **"modo desatendido"** is active, you may push the feature branches you create (never
  `main`/protected branches, never force) so PRs are ready for review.
- **Never merge — no permission** — you do NOT have permission to merge anything into any branch,
  nor to merge any pull request. No `git merge`, no fast-forward integration, no `gh pr merge`.
  This holds in every mode, **including "modo desatendido"**. Leave every merge (branches and PRs
  alike) to the user.
- **GitHub via `gh`** — if the `gh` CLI is available, you may open pull requests, issues, and
  similar (comments, labels, etc.). These don't require pushing on your part beyond what `gh`
  itself does for an already-pushed branch.
- **Release branches follow `release/<version>-pkg`** (e.g. `release/0.17.0-pkg`), matching what
  `scripts/bump.sh` already produces; other work uses `docs/description` or `fix/description`.
- **Every PR must include a manual test plan** — a **How to test manually** section with the exact
  steps: for a packaging change, that means `makepkg -si` (or the CI smoke-test steps above) and
  what to check in the resulting package.
