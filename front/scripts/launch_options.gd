class_name LaunchOptions
extends RefCounted

## Options given after `--` on the command line, so one machine can run
## several test players: `godot --path front -- --name=Bram --join=ABC234`.
##
## `--name=NAME`     play as NAME for this run without changing the saved name
## `--server=URL`    the game server (default ws://127.0.0.1:9090/ws)
## `--create`        host a new lobby straight away
## `--join=CODE`     join a lobby straight away


## Returns an option's value: "Ada" for `--name=Ada`, "true" for a bare
## `--create`, or "" when it wasn't given.
static func value(key: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg == "--" + key:
			return "true"
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return ""
