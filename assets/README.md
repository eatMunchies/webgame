# Game assets

Art for the webgame. Everything here is drawn in [Pixelorama](https://github.com/Orama-Interactive/Pixelorama) 1.2 or later, a free pixel-art editor.

| Path | What it holds |
|------|---------------|
| `sprites/` | Exported, game-ready PNG spritesheets. The game loads only from here. |
| `source/` | Editable Pixelorama projects (`.pxo`), mirroring the `sprites/` layout. Open these to change a sprite. |
| `source/characters/starters/` | Blank projects for drawing a new character part or pet. |

Categories: `characters`, `tiles`, `items`, `ui`. Only `characters` has art so far.

Draw at native size, since the game scales up with nearest-neighbor filtering. Name files and folders in lowercase with underscores.

## Character sheet format

Every character sheet (bodies, parts and pets) is **128x128**: 4 columns by 4 rows of **32x32** frames.

- Columns are walk frames. Column 0 is also the idle pose.
- Rows are facings, top to bottom: **down, left, right, up**.
- Draw each part where it should appear over the body, on a transparent background. Leave a frame empty where the part isn't visible, such as eyes in the "up" row.

In the `.pxo` projects the same 16 frames sit in one timeline, tagged `down`, `left`, `right` and `up`.

## How a character is put together

A player is a stack of sheets drawn on top of each other, so every combination works without drawing it by hand.

```
sprites/characters/
  bodies/<type>_<gender>.png          regular|chibi|lanky x male|female
  parts/<folder>/<item>/<file>.png    one folder per item
```

**Bodies** are drawn in **grayscale** (light gray skin, near-black outline). The game tints them with the player's chosen skin color, so don't color the skin in a body sheet.

**Parts**, layered back to front in this order:

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

Most items can be a single `all.png` drawn on the **regular** body. Add a more specific file only where the shared one looks wrong, for example a chestplate shaped for the female body. Male and female bodies share the same sizes and head and hand positions.

**Shifting.** When a part has no drawing for the current body type (only `<gender>.png` or `all.png`), the game moves it to that body's head or hands. Compared with the regular body, the chibi head and hands sit 4px lower, while the lanky head sits 4px higher and its hands 3px higher. These offsets live in the game client's part catalog (`BODY_ANCHORS`), so redrawing the bodies with different proportions means updating them there.

**Erase color.** Paint pixels pure magenta, `#FF00FF`, in a part to erase the body and any lower parts at that spot. Use it when a part replaces the body instead of covering it. For example, the Fancy Pants stick-figure chest paints magenta over the torso and arms, then draws thin lines in their place. The erase only affects layers below the part in the table above. It must be exactly `#FF00FF` at full opacity; any other shade is drawn as a normal color. Keep it as a swatch in your palette.

**Held items** are drawn once, in the **main (right) hand**: screen-left when facing down, screen-right when facing up, centered when facing sideways. The off hand reuses the same sheet mirrored, and whichever hand is on the far side of the body is drawn behind it.

## Costume sets

Items that share a name prefix belong to one costume and group together in pickers:

| Prefix | Costume |
|--------|---------|
| `template_` | Simple generic starter pieces: caps, a sword, a shield, eyes, mouths and pets. Copy one as a starting point. |
| `fancy_pants_` | Fancy Pants (The Fancy Pants Adventures): spiky hair (with a ponytail on female bodies), stick-figure chest, stick fists, flared pants, squiggle, pencil. |
| `onion_knight_` | Siegmeyer of Catarina (Dark Souls): onion helm, round armor (with a cloth tabard on female bodies), puffy leggings, round gauntlets, Estus flask, zweihander. |
| `pilgrim_` | Town of Salem pilgrim: buckled hat, black coat with white collar (with an apron on female bodies), white cuffs, breeches with buckle shoes, a rolled-up last will, blunderbuss. |
| `bieber_` | Justin Bieber, "Baby" era: swoop haircut, purple hoodie, wristbands, jeans with white high-tops, dog tags, microphone. |
| `kanye_` | Kanye West, Yeezus-era crystal mask: full-head crystal mask, black leather jacket, gloves, baggy pants with tan boots, Jesus piece chain, gold Grammy. |
| `kanye_alex_jones_` | Kanye West on the Alex Jones show: plain black ski mask with an eye slit, black racer jacket (flame-lined hood, VTM TURBO logo, mesh sleeve panels), orange fly swatter. Wear with `kanye_baggy_pants` and `kanye_gloves`. |

All of this art is generated placeholder pixel art meant to be redrawn. Every set except `template_` is fan art of characters or real people owned by, or belonging to, others. That's fine for a personal project, but replace those sets before publishing the game.

## Editing a sprite in Pixelorama

Every sprite has a matching project under `source/`, at the same path with `.pxo` instead of `.png`.

- **Part projects** have two layers: a locked, half-transparent **guide** showing the body the part was drawn on, and the **item** layer above it.
- **Export settings** are saved in each project: a spritesheet of 4 rows, named after the target PNG, exporting **only the item layer**. The guide never ends up in the PNG.

To change a sprite:

1. Open the `.pxo` and draw on the item layer.
2. Save it (File > Save).
3. File > Export. The settings are already filled in. Choose the matching `sprites/` folder (the save location isn't stored in the project), then export over the old PNG.

## Making something new

1. Copy a starter from `source/characters/starters/`. Use `new_part_regular_male.pxo` for a shared `all.png` part, a different body's starter for a body-specific version, or `new_pet.pxo` for a pet.
2. Draw on the `new part` layer, using the guide body underneath.
3. Save it as `source/characters/parts/<folder>/<item_name>/<file>.pxo`.
4. Export as `sprites/characters/parts/<folder>/<item_name>/<file>.png`, where `<file>` is `all` or a body-specific name from the lookup list above.

The item shows up as an option the next time the game runs. A new folder is all it takes.
