# Simple Pet Target

[![Build](https://github.com/joseph3114/SimplePetTarget/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/joseph3114/SimplePetTarget/actions/workflows/build.yml) [![Lint](https://github.com/joseph3114/SimplePetTarget/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/joseph3114/SimplePetTarget/actions/workflows/lint.yml) [![Tests](https://github.com/joseph3114/SimplePetTarget/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/joseph3114/SimplePetTarget/actions/workflows/tests.yml) [![Release](https://img.shields.io/github/v/release/joseph3114/SimplePetTarget)](https://github.com/joseph3114/SimplePetTarget/releases/latest) [![CurseForge](https://img.shields.io/curseforge/v/1794445?label=CurseForge)](https://www.curseforge.com/wow/addons/simple-pet-target)

A World of Warcraft Forever addon that adds a **Pet Target Frame**: a small frame showing whatever your pet is targeting. It looks and behaves like Blizzard's own Target of Target frame.

## Features

- Same design as the default Target of Target frame: round portrait, name, health bar and power bar
- Up to 4 debuffs with cooldown swipes and dispel-type borders, in combat too: they're shown through Blizzard's secure aura display, since the game doesn't let addons read auras in combat. Hover a debuff for its tooltip
- Shows DEAD or UNCONSCIOUS like the default frame
- Left-click to target your pet's target; click-casting and pings work on it too
- Appears automatically whenever your pet has a target, including in combat
- Follows your Blizzard settings for dispellable debuffs and class-icon portraits

## Turning it on or off

**Options › AddOns › Simple Pet Target › Show Pet Target Frame** turns the frame on or off, like Blizzard's Target of Target option.

## Edit Mode

Open Edit Mode and the **Pet Target Frame** shows up with the rest of your frames. A small **Simple Pet Target** panel next to the HUD Edit Mode window has a **Pet Target Frame** checkbox that works like Blizzard's Pet Frame checkbox: uncheck it to leave the frame out of Edit Mode. It's greyed out while the frame is turned off in Options.

Click the frame to open its options:

- **Attach to Pet Frame** (on by default): sits next to your Pet Frame and follows its position and size, like Target of Target does with the Target frame
- **Frame Size**: 100% to 200%, used when the frame isn't attached

When it isn't attached, drag it anywhere. Position, Attach to Pet Frame and Frame Size are saved per Edit Mode layout; the two on/off checkboxes apply to all layouts.

## Libraries

- [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim, for the Edit Mode integration. It is included unmodified, from commit `adfa353` (the first with the WoW Forever fix for its position panel), under its own license in `Libs/LibEditMode/LICENSE.txt`.

## Development

The repository folder is the addon folder. To test changes in game, link it into the AddOns folder and `/reload` after each change, for example from PowerShell:

```powershell
New-Item -ItemType Junction -Path "D:\WoW\World of Warcraft\_forever_\Interface\AddOns\SimplePetTarget" -Target "C:\Users\josep\claude\SimplePetTarget"
```

Releases come from version tags (`vX.Y.Z`; a tag containing `beta` is a beta). CurseForge's automatic packaging builds and publishes the CurseForge file, and the **Release** workflow publishes the same zip as a [GitHub release](https://github.com/joseph3114/SimplePetTarget/releases), with notes from the commit messages since the previous tag. `.pkgmeta` leaves the `assets` folder (logos and the scripts that draw them), the tests, the GitHub workflows, `.luacheckrc`, `CLAUDE.md` and this README out of the package.

### Checks

GitHub Actions runs three checks on every push and pull request, and a fourth workflow on version tags:

- **Build** packages the addon with the same packager CurseForge uses, without uploading it, and checks what went into the zip. The zip is attached to the run.
- **Lint** runs [luacheck](https://github.com/lunarmodules/luacheck) on the addon's code (`.luacheckrc` lists the game API it uses) and checks the XML is well-formed.
- **Tests** loads the addon and LibEditMode, in TOC order, into a stand-in for the game (`tests/wowmock.lua`) and plays through logging in, pet targets, combat, the Options checkbox, Edit Mode and debuffs. The stand-in hides values the way the client does (secret values) and refuses protected changes in combat, so the tests catch code that would break in game. Each run's summary page lists every test.
- **Release** runs on each version tag: it packages the addon the same way, without uploading it to CurseForge, and publishes the zip as a GitHub release.

To run the tests yourself, with Lua 5.1 or LuaJIT:

```sh
lua tests/run.lua
```

Without Lua installed, `python tests/lupa_run.py` runs them with the LuaJIT in the [lupa](https://pypi.org/project/lupa/) package. Name spec files to run only those, for example `lua tests/run.lua 05_debuffs`.

## License

MIT for the addon's own code; see `LICENSE`. LibEditMode keeps its own license.
