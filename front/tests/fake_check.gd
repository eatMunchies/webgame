extends SkillCheck

## A skill check that reports whatever a test tells it to, standing in for
## any kind.


func status() -> String:
	return "%d%%" % roundi(chance * 100)
