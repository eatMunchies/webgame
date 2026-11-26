extends RefCounted

## Models for components shown alone in the style gallery: what each would
## be handed in a real game, made up here so a page needs no server. The
## in-context pages use the Rust fixtures instead (GameClient.load_fixture),
## which play real games.

const NAMES := ["Ada", "Bram", "Cleo", "Dax", "Eve", "Finn", "Gus", "Hepzibah Goode",
		"Ivy", "Jon", "Kit", "Lea", "Mercy Lewis", "Nia", "Otto"]


static func member(n: int, options := {}) -> Dictionary:
	var entry := {
		"number": n, "name": NAMES[n - 1], "alive": true, "is_me": n == 1, "role": "",
		"votes": 0, "connected": true, "is_host": n == 1, "can_whisper": false,
	}
	entry.merge(options, true)
	return entry


static func action(label: String, lot: int, selected := false) -> Dictionary:
	return {"label": label, "command": "/x", "lot": lot, "selected": selected}


static func roster(state: String) -> Dictionary:
	var base := {
		"in_game": true, "night": false, "voting": false, "judging": false, "needed": 0,
		"host_can_start": false, "player_count": 6, "members": [], "actions": [],
	}
	match state:
		"lobby":
			base["in_game"] = false
			base["host_can_start"] = true
			base["player_count"] = 4
			for n in range(1, 5):
				base["members"].append(member(n, {"connected": n != 3}))
		"voting":
			base["voting"] = true
			base["needed"] = 4
			for n in range(1, 7):
				var options := {"can_whisper": n != 1 and n != 4}
				if n == 3:
					options["votes"] = 2
				if n == 4:
					options = {"alive": false, "role": "Doctor"}
				base["members"].append(member(n, options))
				if n != 1 and n != 4:
					base["actions"].append(action("Vote", n - 1, n == 3))
		"trial":
			for n in range(1, 7):
				base["members"].append(member(n))
			base["judging"] = true
			for verdict in ["Guilty", "Innocent", "Abstain"]:
				base["actions"].append(action(verdict, -1, verdict == "Guilty"))
		"night":
			base["night"] = true
			for n in range(1, 7):
				base["members"].append(member(n))
				if n != 1:
					base["actions"].append(action("Interrogate", n - 1, n == 5))
			base["actions"].append(action("Cancel", -1))
		"crowd":
			base["player_count"] = 15
			for n in range(1, 16):
				base["members"].append(member(n, {"alive": n % 5 != 0, "role": "Mafioso" if n % 5 == 0 else ""}))
	return base
