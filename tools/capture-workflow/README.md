# Capture workflow

Small tools for reproducing a visible bug, fixing it and capturing before/after screenshots
without paying a cold build for every change. They drive the client through `cinnabar-mcp`
(see `docs/agents/client-mcp.md`), headless, and never use OS-level input.

| File | Purpose |
| --- | --- |
| `slot.ps1` | Reuse one warm worktree for a new branch from `origin/dev` instead of making a new worktree. |
| `mcp_run.py` | Run a whole scenario against one `cinnabar-mcp` process, then quit the client. |
| `before_capture.ps1` | Capture a scenario on an older commit with the older compiled carriers, then restore the slot. |
| `scenarios/` | JSON step lists: `wear_helmet_third_person`, `inventory_icons`, `first_person_overlay`, `play_with_items`. |

## Why a slot

Each worktree has its own Cargo `build-dir` (`.cargo/config.toml`), so a new worktree is a cold
build (about nine minutes on a laptop) while the edit-and-rerun loop in a warm one is under a minute.
Do not share a build-dir between worktrees, and do not rename or move the slot: its cache is keyed on
its path. `slot.ps1` refuses to run over uncommitted work.

```powershell
$env:CINNABAR_SLOT = 'C:\work\cinnabar-slot'
.\tools\capture-workflow\slot.ps1 fix/some-bug
cargo build -p cinnabar --features developer-control
python -I tools\capture-workflow\mcp_run.py --repo $env:CINNABAR_SLOT `
    --shots $env:TEMP\shots tools\capture-workflow\scenarios\wear_helmet_third_person.json
```

A scenario is a JSON list of `{"tool": ..., "args": {...}}` steps. `$SHOTS` expands to the shots
directory. A step may add `"expect_error": true`, or `"until_text": "<substring>"` with `"timeout"`
seconds to repeat the call until its reply contains that text. `--keep` leaves a visible client
running until its window closes (run it in the background). `CINNABAR_MCP` overrides the
`cinnabar-mcp` binary.

## Before/after screenshots

`before_capture.ps1` detaches the slot at the base commit, swaps in the compiled carriers of the
main checkout (which still hold the old baked icons), builds, runs the scenario and restores the
slot's branch and carriers. Crop and label the two sets identically.

## Lessons

- **Wait for the HUD.** After `connect`, `in_world` is met in about two seconds but the HUD takes
  twenty to fifty. Wait for `{"screen": {"name": "Hud"}}` and then `chunks_loaded` before input.
- **Third person is `key.togglePerspective` (F5); F1 hides the HUD.** A `camera_path` free camera
  keeps the first-person overlays (pumpkin blur, HUD) on, so it is wrong for third-person captures.
  Press F5 once for the view behind the player and twice for the view in front. Use a no-op
  `look` with `relative` and `frames` as a short delay before a screenshot.
- **The local world persists between runs.** Items, position and time carry over. `/give` without
  a selector works, `@s` does not. Teleport (`/tp`) and set the time in every scenario.
- **Poll `wait_for` `inventory_ready` for an item.** Its reply lists the inventory, so
  `until_text` can wait for a `/give` to land. Inventory clicks are pointer clicks at 1280x720.
- **Restoring a file from a backup breaks Cargo's freshness check.** Cargo compares modification
  times, so a file copied back with an old time looks unchanged and a stale test binary is reused.
  Touch the file, or restore with `git checkout`.
- **Baked icons live in `.local/assets/compiled`.** Rebake with
  `cargo run --profile dev -p asset-compiler --bin assetc -- prepare --accept-eula --only icon`.
  Give the slot its own copy of `compiled` so a rebake cannot change another checkout.
- **A PowerShell function named `Git` shadows `git`.** Name helpers `Invoke-Git`, and do not run
  native commands under `$ErrorActionPreference = 'Stop'` without handling their stderr notices.
- **Stop only processes you started, by PID.** A visible session leaves a `--crash-monitor`
  child that is parented to the client.
