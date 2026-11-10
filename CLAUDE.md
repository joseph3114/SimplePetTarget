# Simple Pet Target: notes for working on this repo

A WoW Forever addon (client 1.60.1, game type "camelot", TOC `## Interface: 16001`) that shows `pettarget` in a copy of Blizzard's Target of Target frame, with Edit Mode support through a bundled LibEditMode. The user-facing docs are in `README.md`; this file is the why behind the code.

## Ground rules

- **No AI attribution anywhere**: no `Co-Authored-By: Claude` lines or "Generated with Claude" footers in commits, tags, PRs or release notes.
- **Ask before any push or tag.** A tag publishes a release on CurseForge.
- `CLAUDE.md`, `tests/`, `.github/`, `assets/`, `README.md` and `.luacheckrc` stay out of the CurseForge package (`.pkgmeta` `ignore`, checked by `tests/spec/01_package.lua` and the Build workflow). Add any new dev-only file there too.
- `Libs/LibEditMode` is included **unmodified** (commit `adfa353`, namespaced). Don't edit it; work around it in `SimplePetTarget.lua`.

## Files and load order

TOC order: `Libs/LibEditMode/namespaced.lua`, `Libs/LibEditMode/embed.xml` (the library's Lua files), `SimplePetTarget.xml` (templates), `SimplePetTarget.lua`. The addon gets LibEditMode as `ns.LibEditMode`. The XML templates copy Blizzard's TargetofTargetFrameTemplate with the camelot layout changes baked in. Scripts are set from Lua instead of the XML, because Blizzard's own scripts read secret values.

## Gotchas

### Secret values

Health is always secret. Names, power and aura details are secret in combat for units that aren't player-controlled. The max values (`UnitHealthMax`, `UnitPowerMax`) are secret for those units too.

- Secrets may be passed to sinks: `SetText`, `SetValue`, `SetAlpha`, `SetMinMaxValues`, and C APIs marked `AllowedWhenTainted` (`C_StringUtil.TruncateWhenZero`, `WrapString`, `StripHyperlinks`, `AbbreviateLargeNumbers`, concatenation).
- They may never be compared, used in arithmetic or tested as booleans. Guard anything that compares with `issecretvalue`.
- `Curve:Evaluate` and `NumericFormatter:FormatNumber` don't accept secrets from addon code. Instead, pass the curve to `UnitHealthPercent` or `UnitPowerPercent`, and the game evaluates it.
- The blank-power-text trick (`HideIfMaxIsZero`) gates text on a secret 0 max through `TruncateWhenZero` and `WrapString`, wrapped in an empty hyperlink that `StripHyperlinks` removes. It applies to **power only**: health's max is always secret, and gating health showed raw `|Hsimplepettarget:…` text.

### Taint

- **Never call `AuraUtil` (e.g. `ForEachAura`) from addon code in Edit Mode.** It builds Edit Mode's sample auras under our taint, which then tainted Blizzard's Cooldown Manager and Damage Meter refresh: the `CooldownViewer.lua` / `DamageMeterEntry.lua` "tainted by SimplePetTarget" flood. Edit Mode's sample debuffs come from the secure container instead (`SetEditModePreviewEnabled(true)`).
- **Never write into Blizzard tables or hook Blizzard frames** (no PetFrame hooks; WIM-style taint). The Pet Frame's visibility is polled from the Edit Mode panel's OnUpdate instead.
- Addons can't add to the HUD Edit Mode window without tainting it. That's why our checkbox lives in our own panel beside it.

### Combat and the protected frame

The frame is a `SecureUnitButtonTemplate`. In combat it refuses `Show`, `Hide`, `SetPoint`, `SetParent`, `SetScale`, `RegisterStateDriver`, `EnableMouse` and similar calls.

- `ApplyLayout` defers them with `pendingLayout` until `PLAYER_REGEN_ENABLED`. `SetAlpha` is allowed in combat.
- An alpha-0 frame that is still shown takes clicks. So turning the frame off in combat waits for combat to end (`appliedEnabled`) instead of fading it out.
- Visibility comes from the state driver `[@pettarget,noexists][@pet,dead] hide; show`. `pettarget` has no unit events of its own, so the addon updates on `UNIT_TARGET` (pet) and `UNIT_PET`, plus an OnUpdate.

### Debuffs (secure aura container)

The aura APIs error for addon code while auras are secret.

- Debuffs use `CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")` with one aura group. Its buttons are set up once in `initializeFrame` (icon, dispel border with `PreserveAsset` + `showWithoutDispelType`, cooldown), then locked.
- After that, only `SetTooltipAnchorPoint` may be called, and only while `C_Secrets.ShouldAurasBeSecret()` is false. Never reach the buttons any other way, such as `GetChildren`.
- `initializeFrame` runs behind a secure call barrier that reports errors without passing them on. So `CreateDebuffContainer` checks the button count itself, and `pcall`s the whole setup so the frame works without debuffs.
- The container gets no `UNIT_AURA` for `pettarget`, so `UpdateDebuffs` calls `UpdateAllAuras()`.

### LibEditMode behaviour to work around

- The dialog stays bound to the frame after Edit Mode closes, and a layout change can re-show it. `ResetEditModeDialog` (`Hide` + `Reset`) runs on exit, on combat start, and when the frame leaves Edit Mode.
- `resetSelection` re-shows every selection on enter and exit. A hooked selection `OnShow` hides ours while the frame isn't in Edit Mode.
- Another addon's LibEditMode copy fires `EditModeExternal.hideDialog`, which hides our dialog without unbinding it.

### Settings

- The Options checkbox (`Settings.RegisterAddOnSetting`, `db.enabled`) and the Edit Mode panel checkbox (`db.showInEditMode`) are account-wide.
- Attach, Frame Size and position are per layout (`db.layouts[layoutName]`).
- The panel checkbox checks itself for the session without saving (`checkedForSession`) when the frame is already showing, like Blizzard's Pet Frame checkbox. Its callback acts only on `isUserInput`.

## Checks

- `python tests/lupa_run.py` runs the tests locally (no Lua installed here; lupa's LuaJIT). On GitHub, CI runs `lua5.1 tests/run.lua`. Pass spec names to run a subset, e.g. `05_debuffs`.
- `tests/wowmock.lua` is a stand-in for the client: secret values that error on compare and arithmetic, protected frames that refuse changes in combat (`BLOCKED`), locked aura buttons and `AuraUtil` use (`VIOLATIONS`), and Edit Mode, Settings and LibEditMode templates. When the addon starts using a new API, add it to the mock **and** to `read_globals` in `.luacheckrc`.
- Every test should end with `eq(Problems(G), "", "problems")` where it makes sense.
- GitHub Actions has three workflows, Build, Lint and Tests, each with a README badge. Lua and luacheck come from Ubuntu packages (`lua5.1`, `lua-check`); downloads from lua.org timed out.
- Before suggesting a release, the user tests in game, with BugSack clean, in and out of combat and in Edit Mode.

## Releasing

1. Work happens on `feature/simple-pet-target`. Merge (fast-forward) into `main`, the GitHub default branch.
2. Tag `main` as `vX.Y.Z` and push the tag, **with the user's OK**. CurseForge's webhook packages it: a tag containing `beta` becomes a Beta, anything else a Release. `## Version: @project-version@` is filled in from the tag.
3. The GitHub webhook delivery should return 200, and the file appears on CurseForge as Processing, then goes through review.
4. The same tag runs the **Release** workflow (`.github/workflows/release.yml`). It packages with `-d` (never uploads to CurseForge) and creates the GitHub release with the zip attached. Its notes come from the commit messages since the previous tag, with `Co-Authored-By` and `Signed-off-by` lines stripped, so write commit bodies as release notes. Tags with `beta` or `alpha` become pre-releases. To write the notes by hand instead, create the release first (`gh release create vX.Y.Z --notes-file …`); the workflow then only attaches the zip. To re-attach a zip to an existing tag, run the workflow manually with that tag.

CurseForge project ID: 1794445 (https://www.curseforge.com/wow/addons/simple-pet-target).
