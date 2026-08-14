# Contributing to Yugit

Thanks for considering it. This document covers what you need to know before opening
a PR. The full engineering spec lives in [`docs/04-工程规范.md`](./docs/04-工程规范.md)
(Chinese) — this file is the short version.

## Setup

**Requirements:** macOS 14+, Xcode 16+, Git 2.30+

```bash
git clone https://github.com/Monologuter/Yu-Git.git
cd Yu-Git
./scripts/install-hooks.sh          # run once — installs the quality gates
```

Installing the hooks is not optional. They run the same checks CI would, and catching
a formatting error locally is much cheaper than in review.

| Hook | Runs | On failure |
|---|---|---|
| `pre-commit` | `swift format lint --strict` on staged Swift files | blocks the commit |
| `commit-msg` | Conventional Commits format; rejects AI co-authorship trailers | blocks the commit |
| `pre-push` | full `swift test` | blocks the push |

## Before you open a PR

```bash
# Format (do this before committing — the hook only lints)
swift format --recursive --in-place Packages/ Yugit/

# Test the packages you touched, or all three if unsure
for pkg in GitKit AIKit ForgeKit; do (cd "Packages/$pkg" && swift test); done

# Build the app
xcodebuild -project Yugit.xcodeproj -scheme Yugit -configuration Debug build
```

**Anything user-visible needs to be run for real.** Automated tests cover the Git
layer well and the UI layer barely at all — SwiftUI view logic, focus behaviour,
`.task(id:)` lifecycles, and AppKit interop have all produced bugs that no test in
this repository would have caught. If your change touches the interface, open the app
and use it.

### PR description

Say three things:

1. **Scope** — which modules changed
2. **Verification** — which tests you ran, and what you exercised by hand
3. **Remaining risk** — what you know is untested or uncertain

"Remaining risk" is the valuable one. A PR that says "I didn't test the conflict path
because I couldn't produce a conflict locally" is far more useful than one that
implies everything was covered.

## Commit messages

**English, Conventional Commits.**

```
<type>(<scope>): <imperative summary, <= 72 chars, no period>

<body: why this change, not what changed>

<footer: BREAKING CHANGE / Closes #12>
```

```
feat(GitKit): parse rename entries in porcelain v2 status
fix(diff): stop syntax highlighter hanging on lines containing @
```

Why English when everything else here is Chinese: commit history travels further than
the interface does. It shows up in `git log --oneline`, blame, PR titles, release
notes, and other people's `git bisect` output. The interface is built for Chinese
users; the history is for anyone who might ever read this code.

Code comments and documentation stay Chinese — those have a known audience.

Types: `feat` `fix` `perf` `refactor` `test` `docs` `style` `build` `chore` `revert`.
Scopes: `GitKit` `AIKit` `ForgeKit` `App` `UI` `diff` `history` `server`.

**The body should answer "why".** The most valuable sentence in most commits is
"I tried X first, because Y doesn't work" — that's the one thing you can never
recover by reading the code.

**No AI co-authorship trailers.** The `commit-msg` hook rejects them. This is not
about hiding anything; it's that trailers are for people who can be asked about the
change six months later.

### Granularity

- One commit, one thing
- **Every commit must pass tests on its own** — that's what makes `git bisect` work
- Refactoring and behaviour changes go in separate commits
- Formatting-only changes go in their own commit, or the real diff drowns

## Branching

Light-touch flow:

- Docs and small fixes go straight to `main`
- New modules, multi-commit features, and risky refactors go on `feat/*`, then rebase
  and merge with `--ff-only`
- Tags are annotated (`git tag -a`), on `main` only, and only after the release
  checklist in `docs/04` §11

## Code

Full rules in `docs/04` §4. The ones that come up most:

- **Swift 6 strict concurrency stays on.** Don't downgrade the language mode to make
  an error go away. Every `@unchecked Sendable` needs a comment explaining what makes
  it safe — that annotation silences the check, not the problem.
- **Comments explain why, not what.** `// increment i` is noise. `// -F is required
  here because git parses --grep as a basic regex, so [WIP] would become a character
  class` is worth its line.
- **Don't rely on actors for mutual exclusion.** Actors are re-entrant; a method
  suspended at an `await` releases the actor. When you need real exclusion (holding
  `index.lock`), use the explicit queue — see `RepoActor.queueTail`.
- **Git terms stay in English** everywhere, including the Chinese interface:
  `stage`, `unstage`, `hunk`, `rebase`, `stash`.

## Testing

The house rule, and the reason the suite is worth its size:

> **Every Git edge case that bites us gets a fixture test before the fix is committed.**

And the rule behind that one:

> **Collect real command output before writing a parser.** Don't write it from what
> you assume `git` does.

This is not ceremony. Things this rule has caught that assumptions would not have:

- `--name-status -z` uses a **variable number of fields per record** — one path
  normally, two for renames. Parsing it as alternating status/path silently misaligns
  every entry after the first rename.
- `git diff-tree <merge>` outputs **nothing** for merge commits, and `--first-parent`
  doesn't fix it. You need `<hash>^1 <hash>`.
- `--author` is **always** interpreted as a regex, and `--fixed-strings` does not
  apply to it, so `zhang.san` matches `zhangXsan`.
- `--since=2026-08-14` silently drops that day's commits; the timestamp needs a time
  and a timezone.

Note that all four are *silent* failures. They produce plausible-looking wrong output,
which is exactly what a fixture test built from real bytes catches and an
assumption-driven test does not.

**Also test termination, not just correctness.** A syntax highlighter that colours a
token wrong is a cosmetic bug; one that fails to advance its index hangs the whole app
on a `.vue` file. That happened here. `SyntaxHighlighterTests` now asserts every token
range is non-empty, because an empty range is the signature of a branch that didn't
move forward.

## Dependencies

**Zero third-party dependencies is the default.** Adding one requires a written
justification in the PR: what it does, why the standard library and system frameworks
can't, what it would cost to remove later.

A Git client's job is to be trustworthy with source code. Every dependency is a
supply-chain surface and something that can break on the next macOS release.

For context, the most consequential application of this rule: libgit2 and SwiftGit2
were rejected in favour of shelling out to the system `git`. A bundled library
inevitably diverges from the `git` the user actually has — different version, different
config resolution, hooks that don't fire, credential helpers that don't work.

## Security

- **Never commit credentials.** API keys, tokens, and passwords belong in Keychain
  (client) or `.env` (server, gitignored).
- Test fixtures that *look* like secrets must be obviously fake — see
  `ContextRedactorTests`, which uses `sk-proj-abcdefghijklmnop...`.
- If you find a security issue, don't open a public issue. Reach the maintainer
  privately first.

## Licensing of contributions

This project is [AGPL-3.0](./LICENSE). By opening a pull request you agree that your
contribution is licensed under the same terms.

Note that copyright is not assigned — you keep it. The maintainer retains the right
to offer the project under separate commercial terms, which is only possible because
contributions come in under a license compatible with that. If you're not comfortable
with that arrangement, say so in the PR and we'll work it out before merging rather
than after.

## Questions

Open an issue. If you're unsure whether something is a bug or intended behaviour,
it's usually worth asking before writing the fix — some of the odder-looking
decisions here have a paragraph of reasoning in a nearby comment.
