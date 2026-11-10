class_name BlackjackCheckDef
extends SkillCheckDef

## How a BlackjackCheck is tuned.

## How many decks are shuffled into the shoe.
@export_range(1, 8) var decks := 2
## The chance a won hand is worth, blackjack included.
@export_range(0.0, 1.0, 0.05) var win_chance := 1.0
## The chance a tied hand is worth.
@export_range(0.0, 1.0, 0.05) var push_chance := 0.5
## The chance a lost or busted hand is worth.
@export_range(0.0, 1.0, 0.05) var lose_chance := 0.0
