# Fork workflow for Claude

@AGENTS.md

This checkout is the fork `boIdworks/cinnabar` (remote `fork`) of `cinnabar-mc/cinnabar` (remote `origin`). The user has no write access to `origin`. These rules add to `AGENTS.md`; where they conflict, `AGENTS.md` wins.

## Before every new bug fix

1. `git fetch origin` and `git fetch fork`.
2. Fast-forward the fork's `dev` so it mirrors upstream: `git fetch origin dev:dev` (when `dev` is not checked out), then `git push fork origin/dev:refs/heads/dev`. Never commit to `dev`.
3. Cut the fix branch from `origin/dev`, in its own worktree (see `docs/agents/multi-agent-workflow.md`). This keeps the branch's diff to the fix alone and makes merge conflicts rare.
4. Do not refresh an open PR branch just because it is behind `dev`. Rebase only when there is a real conflict or the user asks.

## One bug, one branch, one PR

- Every distinct bug gets its own branch and its own PR. Never bundle two bugs.
- Add commits to an existing PR only when they change that same bug's fix (review feedback, a case the first fix missed, a failed user test).
- A new problem found while fixing another is reported to the user and fixed on its own branch.
- Name branches `fix/<short-bug-name>`.

## Fixing until the bug is actually fixed

Aim for about 99% confidence before handing a fix to the user:

1. Reproduce the bug in the smallest owning crate and write a regression test that fails before the fix and passes after it.
2. Find the root cause, not a symptom. Check the other callers and code paths that share it.
3. Check the neighbouring cases: edge values, empty and maximum inputs, other platforms, and the behaviour the fix must not change.
4. Run `cargo check --tests -p <touched-crate>`, the touched crate's tests, and the formatter. Do not run full-workspace checks (see `AGENTS.md`).
5. For anything visible in the client, build it so the user can launch it. Use the launch notes below.
6. If a check, test or edge case turns up a gap, keep going. Do not stop at "should work".
7. State plainly what was verified and what only the user can confirm in game.

## The user tests before any PR

- Commit locally with a descriptive message. Do not push or open a PR until the user says the fix tested well.
- After they confirm, push to `fork` and open the PR with `--head boIdworks:<branch>` against `cinnabar-mc/cinnabar` `dev`.
- If the user reports the fix did not work, keep working on the same branch.

## Mechanics specific to this fork

- Commit identity (git has no global one): `git -c user.name=boIdworks -c user.email=351501567+boIdworks@users.noreply.github.com commit ...`.
- Do not add `Co-authored-by` trailers or any Claude/Codex co-author line.
- PR title: start with a fix verb (Fix, Keep, Stop, Restore, Correct, Prevent, Handle, Avoid). `pr-label.yml` labels from the first word and the user cannot change labels afterwards. A title that starts with another word is labelled `new`.
- No labels and no `gh pr edit --attach`. For screenshots, host them on an image-only fork branch and link the raw URL from the PR body.
- Pushing to `origin` returns 403. Only push to `fork`.
- `cargo` lives in `~/.cargo/bin` and needs WinLibs MinGW on `PATH`: `~/AppData/Local/Microsoft/WinGet/Packages/BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe/mingw64/bin`. Tool shells do not inherit either.
- The desktop shortcut opens an old installed Cinnabar. Launch the test build's exe directly.

## Launching a test build (a fresh checkout or worktree won't start without these)

Build with `cargo build --locked -p cinnabar --bin cinnabar -j 4` and launch `target\debug\cinnabar.exe` with the checkout as the working directory. Capture stderr when launching (`Start-Process -RedirectStandardError`): a startup failure prints there and the process just exits.

1. **Exits at once with "could not read required atmosphere asset carrier" or "invalid MCBEENT4 catalog payload":** the checkout has no compiled assets, or they are older than the code. Run `mingw32-make assets` (MinGW on `PATH`) in the checkout. It passes `--accept-eula`, so ask the user before running it. Copying `.local\assets` from another worktree only works while that worktree's code is the same version; carriers from an older `dev` fail to decode. `.local/` is git-ignored.
2. **"Creating new world…" hangs forever (this has happened repeatedly):** the client has no `bedrock-core.exe` and `bedrock-local-server.exe` beside it. `.local\logs\client.log` says `launcher core unavailable: bedrock-core executable not found`. Go is not installed here, so `make play-build` can't build them. Copy both from a worktree that has them, such as `C:\Users\Marley\cinnabar-world-packs\target\debug\`, into this checkout's `target\debug\`, then relaunch. Joining a server doesn't need them.
3. **Which build is running:** this build logs to `.local\logs\client.log` in the checkout (`profile=debug`, `commit=unknown`). `%LOCALAPPDATA%\Cinnabar\logs\client.log` belongs to the installed release.
4. If world creation still fails after the copy, the copied core may be too old for the client's protocol. Say so and ask the user to install Go to build a fresh one, rather than guessing.

## Lessons from past sessions

- **A passing test may not have run.** Fixture-dependent tests (for example `json-ui` HUD tests) print `skipping local vanilla UI fixture test` and return success when `.local/assets/bedrock-samples/<version>/full/resource_pack/ui` is missing. Run them with `-- --nocapture`, check there is no `skipping` line and that the run took real time, and copy that folder from a checkout that has it (git-ignored) when it is absent.
- **Presentation tests need assets that match the branch.** Many `client-ui` presentation tests fail with carrier-format errors when `.local/assets/compiled` was built for a different branch. Prove such failures are not yours by stashing your change and rerunning the same tests.
- **Save disk.** Each worktree's build cache is 9-45 GB (`~/.cargo/build/cinnabar/<hash>`). Reuse an idle worktree by switching its branch (`git switch -c <branch> --track fork/<branch>`) instead of creating a new one. Asset carriers belong to one branch's format, so a worktree that was switched needs `mingw32-make assets` again (ask first: it accepts the Mojang EULA).
- **Rebuilding overwrites the test exe.** Do not rebuild a worktree whose client the user is about to test.
- **Review-comment fixes** go on the existing PR's branch, locally, and are pushed only after the user tests them. Verify each finding against the code first; some are wrong or only theoretical.

## Check the PR is still open before working on it

Before starting or continuing work on any PR (review fixes, tests, rebuilding, pushing), run `gh pr view <number> --repo cinnabar-mc/cinnabar --json state,mergedAt,closedAt`. If it is merged or closed, stop: report it to the user and do not work on it. Check again before pushing and whenever a long task finishes.
