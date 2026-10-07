# webgame

A top-down RPG for the browser.

## Layout

| Path | Purpose |
|------|---------|
| `front/` | Game client (Godot 4.7 project, exported to the web) |
| `api/auth/` | Authentication service |
| `api/db/` | Database |
| `assets/` | Art assets (see below) |

## Game client (`front/`)

Requires [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET). The project uses the Compatibility renderer because the web export requires it, and renders at 320x180, scaled up by whole numbers with no texture filtering so pixel art stays sharp.

To work in the editor, open Godot's Project Manager, choose Import, and select `front/project.godot`. Press F5 to run. The game opens on the wardrobe (character creator preview). To walk around in a test scene, open `scenes/main.tscn` and press F6, then move with WASD or the arrow keys.

From a terminal, the commands below use `godot` to mean the Godot executable. Either add it to your PATH or replace `godot` with its full path.

- Open in the editor: `godot -e --path front`
- Run the game: `godot --path front`
- Run the walking test scene: `godot --path front res://scenes/main.tscn`

`front/assets` is a symlink to the top-level `assets/` folder, so sprites appear in Godot as `res://assets/...`. On Windows, Git checks symlinks out as plain text files unless symlink support is on. Enable Developer Mode, then clone with `git clone -c core.symlinks=true ...`. Godot writes a `.import` file next to each image; commit those.

### Web export

1. One-time: in the editor, Editor > Manage Export Templates > Download and Install.
2. In the editor use Project > Export > Web > Export Project, or from a terminal run `godot --headless --path front --export-release Web`. Either writes `front/build/web/index.html` (gitignored).
3. Browsers won't run the export from a `file://` URL, so serve `front/build/web` with any static file server and open it over `http://`. The preset turns thread support off, so the server doesn't need special COOP/COEP headers. Any static host (itch.io, GitHub Pages, Netlify) works the same way.

## Art assets

Sprites are drawn in [Pixelorama](https://github.com/Orama-Interactive/Pixelorama), a free pixel-art editor.

- `assets/source/` holds the editable Pixelorama project files (`.pxo`), in the same folder layout as `assets/sprites/`. Commit these so art can be reworked later.
- `assets/sprites/` holds exported, game-ready PNG spritesheets. The game loads only from here.

Draw at native size; the game scales up with nearest-neighbor filtering. Name files and folders in lowercase with underscores.

### Character sheet format

Every character sheet (bodies, parts and pets) is **128x128**: 4 columns by 4 rows of **32x32** frames.

- Columns are walk frames. Column 0 is also the idle pose.
- Rows are facings, top to bottom: **down, left, right, up**.
- Draw each part in the same spot it should appear over the body, on a transparent background. Leave a frame empty where the part is not visible, such as eyes in the "up" row.

### Layered characters

A player is a stack of sheets drawn on top of each other, so every combination works without drawing it by hand. Whenever the appearance changes, `CharacterBaker` combines the stack into one sheet, and the game draws that sheet as a single sprite. The code lives in `front/scripts/character/`.

```
assets/sprites/characters/
  bodies/<type>_<gender>.png          regular|chibi|lanky x male|female
  parts/<folder>/<item>/<file>.png    one folder per item
```

Bodies are drawn in **grayscale** (light gray skin, near-black outline). The game tints them with the player's chosen skin color, so do not color the skin in the body sheet.

Parts, drawn back to front in this order:

| Slot | Folder | Shifted to |
|------|--------|-----------|
| Legs | `legs` | |
| Chest | `chest` | |
| Gauntlets | `gauntlets` | hands |
| Eyes | `eyes` | head |
| Mouth | `mouth` | head |
| Accessory | `accessory` | head |
| Hat | `hat` | head |
| Main hand | `held` | hands |
| Off hand | `held` | hands |
| Pet | `pet` | (stands beside the player) |

**Which file is used.** Inside an item folder the game picks the most specific drawing that exists:

1. `<type>_<gender>.png`, for example `chibi_female.png`
2. `<type>.png`, for example `chibi.png`
3. `<gender>.png`, for example `female.png`
4. `all.png`

So most items are a single `all.png` drawn on the **regular** body. Add a more specific file only where the shared one looks wrong, for example a chestplate shaped for the female body. Male and female bodies share the same sizes and head/hand positions.

**Shifting.** When a part has no drawing for the current body type (`<gender>.png` or `all.png`), the game moves it to that body's head or hands using `BODY_ANCHORS` in `front/scripts/character/part_catalog.gd`. The chibi head and hands sit 4px lower than the regular body's, while lanky's head is 4px higher and its hands 3px higher. Change those numbers if your real bodies differ.

**Hiding what's underneath (erase color).** Paint pixels pure magenta, `#FF00FF`, in a part to erase the body and any lower parts at that spot. Use it when a part replaces the body instead of covering it. For example, the Fancy Pants stick-figure chest paints magenta over the torso and arms, then draws thin lines in their place. The erase only affects layers below the part in the table above. Use exactly `#FF00FF` at full opacity; any other shade is drawn as a normal color.

**Held items** are drawn once, in the **main (right) hand**: screen-left when facing down, screen-right when facing up, centered when facing sideways. The off hand reuses the same sheet mirrored, and the game draws whichever hand is on the far side of the body behind it.

**Adding an item:** create `parts/<folder>/<item_name>/all.png` and it shows up in the wardrobe the next time the game runs. No code change is needed. Adding a new slot or body type means editing `SLOTS` or `BODY_TYPES` in `part_catalog.gd`.

**Costume sets** are just items that share a name prefix, so they group together in the dropdowns:

| Prefix | What it is |
|--------|-----------|
| `template_` | Simple generic starter pieces: caps, a sword, a shield, eyes, mouths and pets. Copy one as a starting point for a new item. |
| `fancy_pants_` | Fancy Pants (The Fancy Pants Adventures): spiky hair (with a ponytail on female bodies), stick-figure chest, round stick fists in the gauntlets slot, flared pants, squiggle accessory, pencil. |
| `onion_knight_` | Siegmeyer of Catarina (Dark Souls): onion helm, round armor (with a cloth tabard on female bodies), puffy leggings, round gauntlets, Estus flask accessory, zweihander. |

All of this art is generated placeholder pixel art meant to be redrawn. The Fancy Pants and onion knight sets are fan art of characters owned by others. They're fine for a personal project, but replace them before publishing the game.

### Drawing a part in Pixelorama

1. File > Import the body sheet (for example `assets/sprites/characters/bodies/regular_male.png`) as a **Spritesheet (new project)** with 4 horizontal and 4 vertical frames. You get 16 frames of 32x32.
2. Add a new layer for the item and draw on it in every frame, using the body underneath as a guide. Onion skin helps keep walk frames consistent.
3. Save as `.pxo` under `assets/source/characters/parts/<folder>/<item>/`.
4. Hide the body layer (the eye icon) so only the item is visible.
5. File > Export > Spritesheet tab: direction by rows, 4 rows. Check the preview shows a 4x4 grid, then save to `assets/sprites/characters/parts/<folder>/<item>/all.png`.
6. Run the game. The item appears in the wardrobe dropdowns.

To draw a body-specific version, import that body instead in step 1 and export as `<type>.png` or `<type>_<gender>.png`.
