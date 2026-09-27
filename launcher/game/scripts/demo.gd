extends Node
## Scripted input for captures and the real launch test. It drives the
## launcher through a "demo:0" device in the shared Players autoload, exactly
## as a pad would, so the capture exercises the real input path.
##
##   --demo=browse         right, right, right, left, a pause on each card
##   --demo=soon           browse to the first coming-soon card and press A
##   --demo=power          select the power card and hold A (no quit: stops at 90 %)
##   --autolaunch=<slug>   select <slug>, then press A once

const DEV := "demo:0"

var _steps: Array = []  # [seconds_from_start, state Dictionary]
var _t := 0.0
var _main: Node


func start(main: Node, args: Dictionary) -> void:
	_main = main
	var mode: String = args.get("demo", "")
	if args.has("autolaunch"):
		main.select_slug(args.autolaunch)
		_press(1.5, "a")
	elif mode == "browse":
		var t := 1.2
		for dir in [1, 1, 1, -1]:
			_tap(t, Vector2(dir, 0))
			t += 1.3
	elif mode == "soon":
		for i in main.games.size():
			if not main.games[i].get("playable", true) and main.games[i].get("kind", "") != "power":
				main.carousel.select(i)
				break
		_press(1.5, "a")
	elif mode == "power":
		main.select_slug("power")
		_steps.append([1.0, {"a": true}])
		_steps.append([1.0 + main.POWER_HOLD * 0.9, {}])
	_steps.sort_custom(func(x, y): return x[0] < y[0])
	Players.set_scripted(DEV, {})


func _tap(at: float, dir: Vector2) -> void:
	_steps.append([at, {"move": dir}])
	_steps.append([at + 0.12, {}])


func _press(at: float, button: String) -> void:
	_steps.append([at, {button: true}])
	_steps.append([at + 0.12, {}])


func _process(delta: float) -> void:
	_t += delta
	while not _steps.is_empty() and _steps[0][0] <= _t:
		Players.set_scripted(DEV, _steps.pop_front()[1])
