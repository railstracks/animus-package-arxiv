# animus-package-arxiv

Animus API package: arXiv browsing for agents. Search the arXiv API, cache
papers locally for paginated reading (arXiv's HTML rendering stripped to
text, ~8KB pages), and track phrases with a rotating new-paper poll.
No credentials required — arXiv's public API is credential-free.

## Commands

- `search` — query arXiv (id, title, authors, abstract excerpt per hit)
- `paper abstract` — full metadata + abstract by id (existence check)
- `paper cache` — fetch + cache a paper: HTML rendering → text pages in the
  package filespace (falls back to abstract-only when no rendering exists);
  `include_pdf=true` also archives the PDF binary. A render over the sandbox
  instruction budget degrades to an abstract-only cache flagged
  `degraded="instruction_limit"` (web_fetch the rendering for full text)
  instead of failing
- `paper read` — read one page of a cached paper (`next_page` walks)
- `cache list` / `cache remove` — library management
- `poll` — new-paper check. With a `phrase` arg: one-off check, rotation
  untouched. Without: rotates through the configured list, one phrase per
  invocation. New hits recorded, never auto-cached — triage is the agent's call
- `phrases add` / `phrases remove` / `phrases list` — agent self-configuration
  of the poll rotation (no admin state access needed)

## Query semantics

Plain multi-word queries are AND-joined across all fields (`sovereign default
credit supply` → `all:sovereign AND all:default AND …`) — arXiv otherwise
silently rewrites space-separated terms as **OR**, returning the latest-indexed
papers from random fields (found live by Buffett's field test, Oct 31 2026).
Quoted phrases group; anything with a field prefix (`cat:q-fin.CP`, `ti:`,
`abs:`, `au:`), boolean operator (AND/OR/ANDNOT), or parenthesis passes
through verbatim. Every result echoes `executed_query` — the query arXiv
actually ran, straight from the feed's own title — so server-side rewrites are
always visible.

## Politeness

The sandbox has no sleep; the caller's cadence IS the throttle. Schedule the
poll no tighter than one call per few minutes (arXiv asks for ≥3s between
queries). Sept 13 brownout lesson, carried from the original fetcher.

## State

`phrases` (JSON array of poll queries), `seen` (recent ids, capped 1000),
`library` (cache index), `poll_cursor` (rotation position), `poll_fails`
(consecutive poll failures per phrase; skip-after-3, cleared on success).

⚠️ Upgrades: package state lives on the package row, and current kernels
delete it together with the package on uninstall — state survival across
delete+install is a property of some older kernel images only, NOT a
guarantee. Before upgrading on a current kernel, export the rotation first
(`phrases list`) and re-add it after; `seen` re-seeds on the first poll.

## Build & test

```bash
python3 build.py              # → built/manifest.json (scripts inlined)
lua5.4 tests/run_tests.lua    # offline suite: real fixtures, mock ctx
```

118 checks green against live-fetched fixtures (Oct 31 2026); live e2e proven
against a scratch animusd (install → enable → search → cache → read →
poll rotation → list → remove). The 0.1.3 instruction-limit fix is proven
with a kernel-identical 10M `lua_sethook` witness: the real 1.75MB
math/tables-heavy rendering (2610.36491v1) through the full cache path on a
crypto-less ctx caches html-mode, 26 pages, without tripping.

## Install

Owner-uploaded manifest:
`POST /api/v1/api/packages` (installs disabled; enable via
`PUT .../packages/{id}/enabled`), or via the Animus Registry once published.

Egress: `export.arxiv.org`, `arxiv.org`. License: MIT.
