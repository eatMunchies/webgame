# Design system

How Table of Salem looks and why: the brand book every screen is built from. The values live in code (`front/scripts/ui/design/`); this explains them. The style gallery renders all of it, alone and in the game, at a phone's and a wide window's size: `just gallery` (see [Gallery](#gallery)).

Read [LORE.md](LORE.md) first: the game is a simulation, and that decides which of two visual layers anything belongs to.

## Principles

1. **Played in person.** Everyone sits around one table and talks out loud; each phone is an assistant. The screen shows who is who and what you can do now; the chat is a record and the bots' voice. Nothing should need typing to play.
2. **Phones first.** Every screen works on a portrait phone (405x720) and a wide window (960x540). Check both in the gallery before calling anything done.
3. **Nothing on screen gives your role away.** People glance at each other's phones. Your role, faction and anything that implies them (a faction color, a channel name, an ability's name) appear only on the role card, which you open on purpose.
4. **Timing never leaks.** Night stages always run their full length, whatever happens in them; the UI must not show stage names or end anything early in a way that hints at who acted.
5. **Always say where you are.** A visible caret, the current choice filled in, the prompt saying what to do now, hints only when they apply.
6. **Two layers, never mixed.** A thing is either in-world parchment or the machine's glass (below). A component doesn't borrow the other layer's colors or type.

## The two layers

| Layer | In-world: the simulated Salem | System: the machine |
|---|---|---|
| Theme | `UiTheme.paper()` | `UiTheme.system()` |
| Surface | `ParchmentPanel` (Sheet or Document) | `SystemPanel` (glass, brackets, scanlines) |
| Type | IM Fell English (titles), IM Fell SC (headings), Atkinson Hyperlegible (everything read) | IBM Plex Mono |
| Color | Ink on parchment; wax for the one primary action; dyes for meaning | Light grey on black; one cyan accent |
| Uses | Roster, clock, will, role card, text box, names over the town | Start screen, loading/phase-in, reconnecting, the chat (the session's log), customizer ("subject setup"), every night minigame |

## Color

Raw colors are in `Palette`; components use the semantic names in `Tokens`. Never write a color literal in a UI script: `tests/design_tokens_test.gd` fails on any outside a short allowlist (art tints and skin tones).

### In-world

| Token | Use | Day | Night |
|---|---|---|---|
| `paper_raised` | Text fields, stamped buttons | `#eae0c8` | `#e2cfa6` |
| `paper_surface` | Panels | `#e2d3b4` | `#dcc79c` |
| `paper_sunken` | Disabled, wells | `#d2bf98` | `#cdb589` |
| `paper_edge` | Burnt edges | `#b89b6a` | `#6e4f2c` |
| `INK` | Text, borders, the current choice | `#1f1a14` | same |
| `INK_SECONDARY` | Headings, quiet links | `#4a3f33` | same |
| `INK_FAINT` | Notes, placeholders | `#5e503f` | same |
| `INK_RULE` | Rules and lines (decoration) | `#8c7656` | same |
| `WAX` | The primary action, danger, the caret | `#8e1b1b` | same |
| `GOLD` / `GLOW` | Ornament, night glow (never text) | `#a37a22` / `#e8c060` | same |
| `YOU` | Your own name | woad `#2b4c7e` | same |
| `DEAD` | The dead, struck through | ash `#554b3e` | same |
| `SAFE` / `DANGER` | Innocent / Guilty | verdigris / wax | same |
| `FACTION_*` | Role card only | town verdigris, mafia wax, neutral logwood `#5b3f7a` | same |

Every text ink keeps a contrast of at least 4.5 on day and night paper (`tests/design_tokens_test.gd`). Night only changes the paper: ink stays the same, so text already on screen never needs repainting.

### The machine

| Token | Use | Value |
|---|---|---|
| `SYS_BG` / `SYS_SURFACE` | Glass, fields | `#0a0e10` / `#10171a` |
| `SYS_LINE` | Hairlines | `#2a3a40` |
| `SYS_TEXT` / `SYS_DIM` | Text, notes | `#d7e3e6` / `#7f9399` |
| `SYS_ACCENT` | The one accent: headings, focus, primary | cyan `#46e0e0` |
| `LOG_*` | The chat's lines: said, whisper, game news, the machine's own | text, cyan, amber `#e8c060` (the log's one warm color), dim |
| `SYS_FAULT` | A miss, a failure, the opponent in a fight | `#e0466a` |
| `SYS_WARN` | The one warm color: game news in the log, a grab in a fight | amber `#e8c060` |

### Seats

Each of the 15 seats has a dye (`Tokens.seat(n)`): madder, saffron, weld, verdigris, woad, indigo, logwood, cochineal, walnut, oak gall, ochre, sage, slate, rose madder, umber. A player's number is a parchment numeral on their dye, the same in the roster and the chat. Seat colors say *which player*, never anything about their role.

## Type

Sizes in HUD units (the window's short side is 180; a phone shows 2.25 pixels per unit, a 1080p screen 6). Menus in 1280x720 pass `unit` 4 to `UiTheme`.

| Style | Face | Size | Use |
|---|---|---|---|
| Display | IM Fell English | 14 | Start screen title |
| Title | IM Fell English (system: Plex Mono bold) | 10 | "Day 2", a role's name, a prompt's title |
| Heading | IM Fell English SC (system: Plex Mono bold, cyan) | 7 (6) | Section heads |
| Body | Atkinson Hyperlegible (system: Plex Mono) | 6 | The roster, the chat, buttons |
| Body large | Atkinson / Plex Mono | 8 | What's typed in a text field |
| Caption | Atkinson / Plex Mono | 5 | Small notes that are never tapped |
| Mono huge | Plex Mono | 22 | A minigame's countdown |

The fonts are bundled (`assets/fonts`, all SIL Open Font License) so phones and the web build get the same letters; each falls back to Atkinson, then Godot's own font, for letters it lacks. Labels add no line spacing of their own.

## Space and size

Spacing steps (units): hair 1, xs 2, sm 3, md 4, lg 6, xl 8, xxl 12. Use a step, never an in-between number.

- **Tap targets** on a phone: at least `TOUCH_MIN` 14 units tall (to settle against the roster's space at the roster review).
- **Icons**: 16x16 units, drawn on a 16x16 pixel grid.
- **Rules and borders**: 1 unit.

## Surfaces

- **Sheet** (`ParchmentPanel`, `Tier.SHEET`): the HUD's working panels. Flat edges, faint grain, darker toward the border.
- **Document** (`Tier.DOCUMENT`): things handed to you: the role card, the text box, the will. A torn edge and darker margins.
- **Glass** (`SystemPanel`): the machine's panels. Black at 92%, a hairline, cyan corner brackets, scanlines over everything; a moment of glitch when it opens (`glitch_in()`), never on its own.

Night (`Tokens.use_night(true)`) turns parchment candlelit: warmer, darker at the edges, lighter in the middle. Only the paper changes. The machine has no night.

## Components

| Component | Layer | Where it lives | Use |
|---|---|---|---|
| Button (stamped) | in-world | theme `Button` | Any choice; the current choice is filled ink |
| WaxButton | in-world | theme variation | The one primary action on a screen (Start game, Join): a wax seal, no outline, a darker lip, IM Fell small caps |
| QuietButton | both | theme variation | Secondary actions as text (Cancel, Copy) |
| IconButton | both | theme variation + `Icons` | Will, role card, chat tab; an icon, maybe a word |
| SysPrimary | system | theme variation | The machine's primary action |
| Text field | both | theme `LineEdit` / `TextEdit` | A ruled line on parchment; a boxed field on glass; thick caret |
| ParchmentPanel / SystemPanel | each | `scripts/ui/kit/` | Every panel |
| Icons | both | `Icons.get_icon(name)` | White woodcut icons tinted to the layer |
| SeatBadge | both | `scripts/ui/kit/seat_badge.gd` | A player's number on their seat's dye, numeral centered by the font's measurements; faded for the dead; a pill for two digits |
| Roster | in-world | `scenes/hud/roster.tscn` | Every player and what you can do to each (below) |
| Clock | in-world | `scripts/hud/phase_clock.gd` | The day or night, time and stage, and the town's code with Copy and Leave (below) |
| Chat | system | `scenes/hud/chat_panel.tscn` | The session's log and the box to type in (below) |
| Sheet tab | system | `hud.gd` (`_add_chat_tab`) | The phone's grip on the chat sheet: a tongue of the same glass, three bars, a cyan dot for unread lines |
| SeatBadgeTexture | both | `scripts/ui/kit/seat_badge_texture.gd` | A SeatBadge as a texture (`SeatBadge.texture(n, height)`) for places that take one, like the chat; drawn with the font, sharp at any scale |
| Modal | both | `scripts/ui/kit/modal.gd` | The base of the text box and the card: a dimmed backdrop and one panel (a parchment Document, or glass with `system`), upper middle or middle; Escape or a tap outside closes it, after a 400 ms grace for a phone's echo of the opening tap |
| TextPrompt | both | `scripts/ui/text_prompt.gd` | The text box (below) |
| RoleCard | in-world | `scripts/hud/role_card.gd` | Your role on a card (below) |
| WaxSeal | in-world | `scripts/ui/kit/wax_seal.gd` | A round wax seal pressed with a letter: the role card's faction mark |
| Minigame panel | system | `scenes/main/minigame_overlay.tscn` | The night's skill checks and fights (below) |
| SimBackdrop | system | `scripts/ui/kit/sim_backdrop.gd` | The machine's menus' background: a faint grid on near-black |
| Notice | system | `scripts/ui/kit/notice.gd` | The machine speaking about itself: a glass pane at the top of the town, `say(lines)` / `clear()` |
| Herald | in-world | `scripts/hud/herald.gd` | Salem telling a morning's deaths and an execution: a Sheet at the top of the town with a Title (with the player's SeatBadge right before their name, kept on the same line, when it's about one) and lines that fade in one at a time (Body for the causes, Dim for the role, Heading for "Rest in peace."), and the last will on a torn Document under it. 170 units wide at most, narrower in the middle column of a wide screen, and centered across the town's part of the screen; never takes input |

More components (modal, card, sheet tab) arrive with the screens that use them; each gets a row here.

### The roster

- A Sheet. The prompt is a Title saying what to do now in Salem's words ("The Town Votes", "Night", "Judge the Accused"); the votes a trial needs follow in wax, close under it.
- Rows are at least `TOUCH_MIN` (14 units) tall; badge, name (your own in woad, bold), a caption note, then buttons: the ballot-box icon to vote (plain on the paper like the whisper icon, wax red once it's your vote), stamped buttons for other actions, the whisper icon; icons at 13 units.
- **Role-neutral labels.** Only actions everyone has say what they are (Vote, Guilty, Innocent, Abstain, Cancel, Unvote). A role's own action reads **Choose** (aimed at a player) or **Use** (alone), and the prompt says "Night" (or "Day" for the Jailer's pick), so an onlooker learns nothing.
- Verdicts carry meaning in ink color: Guilty wax, Innocent verdigris.
- The dead: ash, struck through, faded badge, revealed role as the note.

### The clock

- A Sheet at the top of the Info column (a wide screen) or across the top (a phone). A sun or moon in secondary ink, the title in IM Fell, the time in Atkinson bold on the right, wax red for the last five seconds; the stage under it in secondary ink.
- Under a rule, the town's code: "Town" in small caps, the code in bold, a copy icon (the code reads "Copied" for a moment, inline, no toast) and a leave icon, which asks again inline: the first tap turns it wax red and the row reads "Tap again to leave" for 3 seconds, and only a second tap leaves (a phone's echo of the first tap, within 400 ms, doesn't count).
- At night only the choosing stage and its timer show (timing never leaks).
- Reconnecting: Salem doesn't notice. The sheet fades to 45% and its time stops; the machine's Notice says "desync detected, resyncing".

### The chat

- The chat is the machine's log of the session, not part of Salem: glass, Plex Mono, and see-through (`LOG_GLASS_ALPHA`) so the town shows behind it on a phone. Parchment there made a phone one wall of bright paper and hid the town.
- On a wide screen it fills the clock's column; on a phone it's a sheet over the town with a tab on its top edge.
- Lines by kind (`Tokens.LOG_*`), at the small mono size (Plex runs large): said in light grey after the speaker's SeatBadge (7 units, the line's number dropped since the badge has it), whispers in cyan, game news in amber, the machine's own lines dim after `> `. Errors keep their `!`. Amber is the log's one color beyond the machine's cyan, so news stands out from talk.
- The box is the glass's boxed field; Send is the envelope icon (dim, cyan on hover), not a primary button, since Start game is the screen's primary action.
- The Last will and role buttons under the roster are stamped paper buttons with the woodcut will and role icons.

### The minigame panel

- The machine's glass (`MinigameOverlay` is a `SystemPanel`), glitching in when something that counts starts. The game's name in the cyan heading, lower case; the time left in mono.
- The countdown before a skill check or fight reads `> evaluation` or `> confrontation`, the game's name dim under it, then a big mono 3, 2, 1.
- Results in the machine's voice: "evaluation passed", "evaluation failed. your action won't work tonight.", "confrontation won", "confrontation lost".
- Fights: you in cyan, the masked opponent in `SYS_FAULT`; a strike in light grey, a grab in amber (`SYS_WARN`), a guard in light grey; empty pips and bars faint. Buttons are the machine's.
- Every game is drawn as the machine's simulation, from `SkillCheck`'s `SIM_*` palette: a dark field with a faint grid and a thin edge (`ArcadeCheck.fit_field`), solid things (ground, pipes, blocks, cards) in the glass's surface color with grey edges, what the player moves in cyan (`SIM_PLAYER`), what they aim for in amber (`SIM_TARGET`: the flag, fruit), danger in `SIM_FAULT` (bombs, red suits), text in Plex Mono. A hit is cyan and a miss `SYS_FAULT`. Card Memory's faces differ by shape first, then by one of four colors.

### The start screen

The machine's screen, over the plaza where the simulation loads (the phase-in into the town is unchanged). A SystemPanel with TABLE OF SALEM (Title) and "> simulation: salem, 1692" (Accent); the subject's name; [host] (SysPrimary) or [key] [join]; "practice evaluations" (quiet) for the minigame tester; a status line, dim while connecting and `SYS_FAULT` when refused. Fields type at the mono body size (typing happens in the text box, on glass here). The hint over the house is cyan mono bold with a dark outline.

### The customizer ("subject setup") and the minigame tester

The machine's menus, laid out in 1280x720 units (`UiTheme.system(4)`). Behind them a `SimBackdrop`: near-black with a faint grid, darker toward the corners. The customizer's pedestal is a SystemPanel headed "> subject setup" over the subject's name, and the character stands on a projection pad (a dark disc with a cyan rim) instead of a stone plinth. Tabs, picture tiles (`ItemTile`) and checkboxes come from the system theme: the open tab and the chosen tile ringed in cyan. Words are lower case; Save is the machine's primary. The minigame tester ("evaluations") uses the same theme at the HUD's units, its list at the small mono size.

### Night

`town.gd` turns on `Tokens.use_night` at nightfall, so every parchment panel turns candlelit, and fades in a candle vignette over the town (`shaders/candle_vignette.gdshader`, colors `Tokens.NIGHT_CANDLE` and `NIGHT_DARK`): a warm pool of light centered on the part of the screen the town shows through, dark toward the edges. It is alpha-blended, not multiplied, and its uniforms are all set from code: the Compatibility renderer the web build uses doesn't draw `blend_mul`.

### The text box

A Modal in the upper middle (clear of a phone's keyboard), 220 units wide at most: the title in IM Fell, the paper's ruled field (wax when focused, a thick wax caret that doesn't blink), then Paste (a quiet button with the paste icon, when asked for), Cancel (quiet) and the confirm as a wax seal ("Send", "Save", "Join"). On the machine's screens the same on glass, with a cyan primary.

### The role card

A Modal in the middle, 200 units wide at most, on a torn Document: a WaxSeal in the faction's color with its initial, the role's name (Title) and category (Dim), the close icon; a rule; then Ability, Goal, and when they apply Your target and Your team, each a small-caps Heading over Body text. A spectator's card has no seal.

## Modals and dialogs

- **Inline by default.** Results, refusals and status show where the player is already looking: the roster's prompt, a status line, the chat log.
- **The text box (TextPrompt)** is only for typing: a whisper, the will, the lobby code and name, the chat on a phone. It opens in the upper middle, clear of a phone's keyboard. Never use it to show or confirm something.
- **A card** is for reading something on purpose, or once at a natural moment: your role at the start of a game. One at a time; Close, Escape or a tap outside closes it. **Anything that reveals a role or faction lives only in a card.**
- **A sheet** is a panel that slides over the town on a phone: only the chat.
- **A notice** is the machine speaking about itself (reconnecting, connection lost, loading). It never blocks input.
- **No confirmation dialogs.** People are talking; a destructive action (Leave) asks again inline if it must.
- **A herald's banner** is Salem announcing something to everyone at once (a death, an execution), timed by the server, over the top of the town. It never takes input and goes away by itself.
- **Stacking**: town < HUD < sheet < herald < minigame < notice < card < text box.

## Display cases

Every component is checked in each case that applies to it:

- **Screen**: phone 405x720, wide 960x540.
- **Time**: day, candlelit night.
- **You**: alive, dead, spectator; host or not.
- **Game**: lobby, in a game, game over.
- **Content**: 4 players and 15; short and long names; empty and full chat.

## Icons

- 16x16 pixels, one color (white, tinted by the UI: ink on parchment, `SYS_TEXT` on glass), no antialiasing.
- Woodcut style: bold strokes, two-pixel lines where it reads better than one, flat shapes, no gradients.
- Drawn as text in `front/tools/icons/make_icons.gd` (run it to rebuild `assets/sprites/ui/icons/`). An artist can redraw any PNG in Pixelorama and take it out of that script.
- The set: will, role, whisper, vote, chat, dead, day, night, time, host, customize, paste, copy, leave, close, send.

## Gallery

`just gallery` renders every page in `front/tools/gallery/pages/` at 405x720 and 960x540 to `front/reports/gallery/`, with an `index.html` showing both sizes side by side; `just gallery type buttons` renders just those. Pages build from the same tokens and components as the game. Add a page with each new component, alone and in context.
