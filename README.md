<div align="center">

# 驭Git · Yugit

**A native macOS Git client built for the age of AI-written code.**

*AI writes your code — Yugit helps you command it.*

[![Stars](https://img.shields.io/github/stars/Monologuter/Yu-Git?style=flat&logo=github)](https://github.com/Monologuter/Yu-Git/stargazers)
[![Forks](https://img.shields.io/github/forks/Monologuter/Yu-Git?style=flat&logo=github)](https://github.com/Monologuter/Yu-Git/network/members)
[![Issues](https://img.shields.io/github/issues/Monologuter/Yu-Git)](https://github.com/Monologuter/Yu-Git/issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/Monologuter/Yu-Git)](https://github.com/Monologuter/Yu-Git/pulls)
[![Last commit](https://img.shields.io/github/last-commit/Monologuter/Yu-Git)](https://github.com/Monologuter/Yu-Git/commits/main)

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-blue)](https://developer.apple.com/xcode/swiftui/)
[![Tests](https://img.shields.io/badge/tests-561%20passing-brightgreen)](#testing)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](./LICENSE)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-success)](#why-zero-dependencies)

[English](./README.md) · [简体中文](./README.zh-CN.md)

</div>

---

## Why another Git client?

Because the way we write code changed, and Git clients didn't.

When an agent produces four hundred lines across nine files in thirty seconds, the
bottleneck is no longer *writing* the change — it's **understanding, verifying, and
splitting** it before it becomes a commit. Existing clients still assume you wrote
every line yourself and remember why.

Yugit is built around that shift:

- **Read a change you didn't write.** Word-level inline diffs, syntax highlighting,
  and AI explanations in plain Chinese — for the diff, the commit, or the conflict.
- **Split what an agent dumped.** Stage by hunk or by individual line, group a
  sprawling change into several coherent commits, and let AI propose the grouping.
- **Undo anything.** Every destructive operation is preceded by an automatic snapshot.
  A rebase that went wrong is one click from being unwound.

And one thing that isn't about AI at all: **the entire interface is in Chinese**,
written by someone who uses Git in Chinese daily — not machine-translated menu strings.
Git terminology (`stage`, `rebase`, `hunk`) stays in English, because that's what
people actually say.

## Highlights

### Understanding changes

- **Word-level inline diff** — when a line changes by one identifier, only that
  identifier is highlighted, not the whole line
- **Syntax highlighting** for 12 language families, tokenized per line so it stays
  correct at hunk boundaries
- **AI explanations** in Chinese for any diff, commit, or merge conflict
- **Blame with AI attribution** — see which lines came from a human and which from
  an agent
- **Instant full-repo search** across commits, messages, file contents, and branches

### Composing commits

- **Hunk-level and line-level staging** — the diff parser and patch builder are
  structurally symmetric, locked by round-trip tests, so partial staging never
  corrupts the working tree
- **Batch commit** — split one large change into several commits, with AI-suggested
  grouping
- **AI-drafted commit messages** that land directly in an editable field, not behind
  an accept/reject dialog
- **AI diff review** before you commit

### Operating safely

- **Timeline with undo** — every write goes through a single entry point, and
  dangerous operations snapshot first. `refs/yugit/*` keeps snapshots out of your
  history
- **Hazard dialogs** that answer three questions at once: what will happen, is it
  reversible, and how to reverse it
- **Visual interactive rebase** — drag to reorder, squash, reword
- **Three-way merge editor** for conflicts
- **Transparent command layer** — every operation shows the equivalent `git` command
  with a Chinese annotation, so the app teaches Git rather than hiding it

### Working at scale

- **50,000-commit repositories** scroll at 60fps — the commit list and diff viewer are
  AppKit, everything else is SwiftUI
- **Parallel workspaces** via `git worktree`
- **File tree** for change lists with hundreds of entries, with single-child
  directory chains collapsed
- **Filter everything** — branches, changed files, and commit history (by message,
  author, or date; the history filter runs in Git, not on the loaded page)

### Integrations

- **GitHub / GitLab (incl. self-hosted) / Gitee** — list and create PRs and MRs
- **Bring your own API key** — Anthropic and OpenAI-compatible protocols, keys stored
  in Keychain, never in config files, never synced to iCloud
- **Optional subscription service** for those who'd rather not manage keys

## Installation

> **No signed release yet.** Signing and notarization are pending, so for now you
> build from source. This is stated plainly rather than shipping an unsigned binary
> that Gatekeeper will block with a confusing message.

**Requirements:** macOS 14+, Xcode 16+, Git 2.30+

```bash
git clone https://github.com/Monologuter/Yu-Git.git
cd Yu-Git
./scripts/install-hooks.sh          # one-time: installs the quality gates
xcodebuild -project Yugit.xcodeproj -scheme Yugit -configuration Release build
```

The built app lands in Xcode's DerivedData; open it from there, or build and run
directly in Xcode.

## Testing

```bash
for pkg in GitKit AIKit ForgeKit; do (cd "Packages/$pkg" && swift test); done
```

561 tests across 58 suites. The suite is deliberately weighted toward **Git edge cases
observed from real command output** rather than mocked behavior — CRLF conflict
markers, renames that lose their pairing when path-filtered, merge commits that
`diff-tree` silently returns nothing for, paths with spaces and CJK characters.

The house rule: every Git edge case that bites us gets a fixture test before the fix
is committed.

## Architecture

```
Packages/
  GitKit/     Process execution, porcelain parsing, staging, branches, remotes,
              search, timeline snapshots, rebase, conflicts, worktrees, blame,
              syntax highlighting, inline diff
  AIKit/      Anthropic + OpenAI-compatible providers, SSE, Keychain, context
              redaction, commit messages, explanations, conflict resolution
  ForgeKit/   GitHub / GitLab / Gitee pull requests
Yugit/        The app: three-pane window, command palette, timeline, settings,
              visual rebase, merge editor, review panel, onboarding
server/       Cloud gateway (Go + PostgreSQL) for the subscription service
```

Three rules hold the design together:

1. **Every repository write goes through `RepoActor.perform(_ op: GitOperation)`.**
   This single entry point is what makes timeline undo possible. Writing to the
   repository any other way is a bug, not a shortcut.
2. **Every `GitOperation` carries its equivalent Git command and a Chinese
   annotation** as metadata. The transparent command layer and the command palette
   both consume it, so they can never drift from what actually runs.
3. **`DiffParser` and `PatchBuilder` are structurally symmetric, locked by round-trip
   tests.** This is the foundation of hunk- and line-level staging not corrupting
   your working tree.

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Language | Swift 6, strict concurrency | Data-race safety enforced at compile time |
| UI | SwiftUI, with AppKit for the commit list and diff viewer | SwiftUI's `List` can't hold 60fps at 50k rows; `NSTableView`'s row reuse can |
| Git engine | System `git` CLI + porcelain parsing (`-z`, `core.quotepath=false`) | Matches the user's own Git exactly — same version, same config, same hooks, same credential helpers |
| AI | Anthropic native + OpenAI-compatible, user-supplied keys | No vendor lock-in; keys stay in Keychain |
| Server | Go + PostgreSQL | 11MB resident; the gateway does no inference, only proxying and metering |
| Dependencies | **Zero third-party** | See below |

### Why zero dependencies

A Git client's job is to be trustworthy with your source code. Every dependency is a
supply-chain surface and a thing that can break on the next macOS release. Adding one
requires a written justification.

The most consequential instance: **libgit2 / SwiftGit2 were rejected** in favor of
shelling out to the system `git`. A bundled library inevitably diverges from the
`git` the user actually has — different version, different config resolution,
hooks that don't fire, credential helpers that don't work. Parsing porcelain output
is more tedious, but it means what Yugit shows is what `git` would do.

## Privacy

- **Local Git functionality is free forever**, including private repositories. There
  is no subscription gate on basic features and there never will be.
- **AI is strictly optional.** The app is fully usable without configuring any provider.
- Requests go **directly to the provider you configured**. Nothing is proxied through
  our servers unless you explicitly subscribe to the cloud service.
- `.env` files, private keys, and credentials are **never sent**, and you're told
  which files were excluded before each request.
- The cloud gateway, if you use it, **stores no source code and no request content** —
  only token counts for metering.

## Documentation

| Document | Contents |
|---|---|
| [`docs/01`](./docs/01-竞品调研与功能设计.md) | Competitive analysis of 13 clients; the reasoning behind 8 differentiating designs |
| [`docs/02`](./docs/02-产品需求文档.md) | PRD — positioning, users, versioned requirements, AI design rules, business model |
| [`docs/03`](./docs/03-实现计划.md) | Architecture, milestones, risk register, acceptance criteria |
| [`docs/04`](./docs/04-工程规范.md) | Engineering conventions — branching, commits, code, testing, security, release |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | How to contribute |
| [`server/README.md`](./server/README.md) | Cloud gateway deployment |

## Status

All milestones in `docs/03` are implemented — v0.1 through v2.0 plus the items listed
as long-term. Current version is **v2.2.0**.

Remaining work is release engineering: code signing and notarization, performance
benchmarking on very large repositories, and end-to-end verification with real
provider keys.

## License

[GNU AGPL-3.0](./LICENSE).

You may use, study, modify and redistribute this software. If you modify it, your
changes must be released under the same license — **including when you run the
modified version as a network service**. That last clause is the reason AGPL was
chosen over MIT or GPL: the cloud gateway in `server/` is exactly the kind of thing
someone could fork, point at their own paid backend, and never publish. AGPL closes
that path while leaving every legitimate use open.

Copyright remains with the author, so commercial licensing on different terms is
available on request.

## Acknowledgements

The competitive analysis in `docs/01` studied Fork, Tower, GitKraken, Sourcetree,
SmartGit, GitButler, Lazygit, Sublime Merge, GitHub Desktop, Gitless, Magit, Git
Cola, and GitUp. Several designs here are direct responses to what those tools got
right — and to what they got wrong.

The layout of this README follows [cc-haha](https://github.com/NanmiCoder/cc-haha).
