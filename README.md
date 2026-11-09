# Simple Pet Target

A World of Warcraft Forever addon that adds a **Pet Target Frame**: a small frame showing whatever your pet is targeting. It looks and behaves like Blizzard's own Target of Target frame.

> **Beta:** debuffs show out of combat only for now. The game blocks addons from reading auras in combat; a version that shows them through Blizzard's secure aura display is in progress.

## Features

- Same design as the default Target of Target frame: round portrait, name, health bar and power bar
- Up to 4 debuffs with cooldown swipes and dispel-type borders; hover a debuff for its tooltip
- Shows DEAD or UNCONSCIOUS like the default frame
- Left-click to target your pet's target; click-casting and pings work on it too
- Appears automatically whenever your pet has a target, including in combat
- Follows your Blizzard settings for dispellable debuffs and class-icon portraits

## Edit Mode

Open Edit Mode and the **Pet Target Frame** shows up with the rest of your frames. Click it to open its options:

- **Show Pet Target Frame**: turn the frame on or off
- **Attach to Pet Frame** (on by default): sits next to your Pet Frame and follows its position and size, like Target of Target does with the Target frame
- **Frame Size**: 100% to 200%, used when the frame isn't attached

When it isn't attached, drag it anywhere. Position and options are saved per Edit Mode layout.

## Libraries

- [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim, for the Edit Mode integration. It is included unmodified, from commit `adfa353` (the first with the WoW Forever fix for its position panel), under its own license in `Libs/LibEditMode/LICENSE.txt`.

## Development

The repository folder is the addon folder. To test changes in game, link it into the AddOns folder and `/reload` after each change, for example from PowerShell:

```powershell
New-Item -ItemType Junction -Path "D:\WoW\World of Warcraft\_forever_\Interface\AddOns\SimplePetTarget" -Target "C:\Users\josep\claude\SimplePetTarget"
```

Releases are built by CurseForge's automatic packaging from tagged commits. `.pkgmeta` leaves the `assets` folder (logos and the scripts that draw them) and this README out of the package.

## License

MIT for the addon's own code; see `LICENSE`. LibEditMode keeps its own license.
