# Lore

The story behind Table of Salem's look. It decides which of the two visual layers a thing belongs to (see [DESIGN.md](DESIGN.md)) and how its words are written. Names marked *(placeholder)* are proposals for the owner to rename; once renamed, update them here and in any copy that uses them.

## The premise

Salem, 1692, never happened the way the players see it. It is a **simulation**, run by a crime family to train an AI in deception.

The family *(placeholder: **the Vescari Family**)* needs its people to lie well: to the police, in court, to rivals, to each other. So it built a machine *(placeholder: **the Loom**)* that drops subjects into the memories of a town on trial, where everyone is suspicious and anyone can be accused. Some subjects are handed a mafia role and must lie, kill and survive; the rest are townsfolk trying to find them. Every lie, every vote and every desperate defense is recorded. The family's AI *(placeholder: **VESPER**)* studies the mafia side above all: which deceptions work, which get you hanged, how people talk their way out.

It works like reliving someone else's memories: the subject wakes in a house in Salem, in someone else's life, and the town assembles around them. That is the start screen's house and the phase-in that grows the town from it.

The players around the table are those subjects. They don't need to know any of this to play. The UI just never pretends the machine isn't there.

## Two layers

| | In-world (the simulated Salem) | System (the Loom) |
|---|---|---|
| What it is | The memory the subjects are living | The machine running it, and its view of them |
| Looks like | Parchment, iron-gall ink, wax seals, woodcut icons | Black glass, monospace, one cyan accent, scanlines |
| Speaks like | A 1692 town clerk: plain, period, a little formal | A terminal: terse, lower case, `>` prompts |
| Where | The roster, the clock, the role card, the will, the text box | The start screen, loading and phase-in, reconnecting, the chat (its log of the session), the customizer, every night minigame |

**Why night minigames belong to the machine:** at night the Loom tests its subjects. Skill checks and fights are its evaluations, so they show through its interface, not the town's.

## Vocabulary

Use these words for the machine's side; in-world text stays in Salem's own words.

| Game thing | The machine calls it | In-world, Salem calls it |
|---|---|---|
| A player | subject | a townsperson, by name |
| A lobby | session *(code: the session key)* | the town |
| Joining / the phase-in | sync, memory sync | arriving |
| A game | run *(placeholder: "run 7")* | the trial |
| Reconnecting | desync, resyncing | (nothing; Salem doesn't notice) |
| The customizer | subject setup | |
| A skill check | evaluation | |
| A fight | confrontation | an attack in the night |
| Your role | assignment | your station / your calling |
| The chat | the log | |

## Tone

- **In-world copy** is plain and period without being hard to read: "The Town Votes", "Day the Second", "Whisper to 2 Bram". No thee-and-thou; no modern slang.
- **System copy** is short, lower case, and factual, like a log: `> subject: ada`, `> memory sync 42%`, `> desync detected, resyncing`. It never jokes and never explains the lore outright.
- Never reveal a role through either voice (see the privacy rules in DESIGN.md).

## Open questions for the owner

- The family's, the machine's and the AI's names.
- Whether subjects know they're in a simulation (does the in-world text ever glitch knowingly?).
- Whether a game's end shows the machine's evaluation of the mafia side (a "debrief" screen).
