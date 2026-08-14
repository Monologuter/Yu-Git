## What changed

<!-- One or two sentences. The "why" belongs in the commit body. -->

## Scope

<!-- Which modules: GitKit / AIKit / ForgeKit / App / server / docs -->

## Verification

- [ ] `swift format --recursive --in-place Packages/ Yugit/`
- [ ] `swift test` passes for the affected packages
- [ ] App builds
- [ ] Ran it by hand (required for anything user-visible)

<!-- Say what you actually exercised. "Opened a repo with 200 changed files and
     staged a directory" is useful; "tested" is not. -->

## Remaining risk

<!-- What's untested or uncertain. This is the most useful section — a PR that
     admits "couldn't reproduce a conflict locally so that path is untested"
     is far more valuable than one that implies full coverage. -->

## Git edge cases

<!-- If this touches Git parsing: did you collect real command output first?
     Paste the relevant bytes. If you added a fixture test, link it. -->
