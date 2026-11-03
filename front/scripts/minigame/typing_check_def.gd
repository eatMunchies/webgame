class_name TypingCheckDef
extends SkillCheckDef

## How a TypingCheck is tuned.

## The wordbank: keebsmith's words.json, lists of words by name.
@export var words: JSON = preload("res://skill_checks/words.json")
## Which list in `words` to draw from.
@export var word_list := "commonWords"
## How many words the check takes. Each one typed right is an equal share of
## the chance.
@export_range(1, 20) var word_count := 4
## Longer words in the list are left out.
@export_range(1, 20) var max_word_length := 6


## The words a check can draw from.
func word_pool() -> PackedStringArray:
	var pool := PackedStringArray()
	var lists: Dictionary = words.data if words != null else {}
	var list: Dictionary = lists.get(word_list, {})
	for word: String in list.get("words", []):
		if word.length() <= max_word_length:
			pool.append(word)
	return pool
