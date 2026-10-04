extends Node2D

## 临时验证：自动攀附 + 蹬墙跳仍然可用。用完即删。

const PLAYER_SCENE := preload("res://Scenes/Entities/player.tscn")
const ACTIONS := ["left", "right", "up", "down", "jump", "dash", "grab", "reset", "interact"]
const WALL_X := 16.0
const STAND_X := 11.0

var player

func _ready() -> void:
	_add_static(Rect2(-2000, 0, 4000, 128))       # 地面，顶面 y=0
	_add_static(Rect2(WALL_X, -800, 200, 800))    # 右侧墙，左表面 x=16
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	await _run()
	get_tree().quit()

func _add_static(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	col.shape = shape
	col.position = r.position + r.size * 0.5
	body.add_child(col)
	add_child(body)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

func _state_name() -> String:
	return ["NORMAL", "DASH", "CLIMB", "DEAD"][player.state]

func _log(tag: String) -> void:
	print("%-30s 位置=(%6.1f,%6.1f) 速度=(%7.1f,%7.1f) 状态=%-6s 体力=%5.1f" % [
		tag, player.global_position.x, player.global_position.y,
		player.velocity.x, player.velocity.y, _state_name(), player.stamina])

func _spawn(y: float, auto: bool) -> void:
	_release_all()
	player.auto_climb = auto
	player.global_position = Vector2(STAND_X, y)
	player.velocity = Vector2.ZERO
	player.state = 0
	player._set_ducking(false)
	player.stamina = player.climb_max_stamina
	player.dashes = player.max_dashes
	player.dash_jump_timer = 0.0
	player.dash_refill_jump_timer = 0.0
	player.super_speed_timer = 0.0
	player.last_dash_dir = Vector2.ZERO
	player.facing = 1
	await _frames(2)

func _run() -> void:
	print("================ A. 自动攀附：空中贴到面前的墙 ================")
	await _spawn(-40.0, true)
	Input.action_press("right")     # 朝墙，不按 Z
	await _frames(16)
	_log("A 什么都没按抓墙键")

	print("================ B. 站在地面上靠近墙 ================")
	await _spawn(0.0, true)
	Input.action_press("right")
	await _frames(16)
	_log("B 站在地上不应该粘住")

	print("================ C. 自动攀附中：按反方向起跳 ================")
	await _spawn(-40.0, true)
	Input.action_press("right")
	await _frames(16)
	Input.action_release("right")
	Input.action_press("left")
	Input.action_press("jump")
	await _frames(2)
	_log("C 反方向+跳（蹬墙跳）")

	print("================ D. 自动攀附中：按同方向起跳 ================")
	await _spawn(-40.0, true)
	Input.action_press("right")
	await _frames(16)
	var stamina_before: float = player.stamina
	Input.action_press("jump")
	await _frames(2)
	_log("D 同方向+跳（贴墙跳）")
	print("   贴墙跳消耗体力：%.1f" % [stamina_before - player.stamina])

	print("================ E. 自动攀附下，上斜冲刺撞墙 + 跳 ================")
	await _spawn(-20.0, true)
	Input.action_press("right")
	await _frames(4)
	Input.action_press("up")
	Input.action_press("dash")
	await _frames(1)
	Input.action_release("dash")
	Input.action_press("jump")      # 冲刺中按下并一直按住
	for i in range(2, 14):
		await _frames(1)
		if i in [6, 10, 13]:
			_log("E dash 后 %d 帧" % i)

	print("================ F. 关掉自动攀附（回归对照）================")
	await _spawn(-40.0, false)
	Input.action_press("right")     # 不按 Z
	await _frames(16)
	_log("F 不按 Z")
	Input.action_press("grab")      # 再按 Z
	await _frames(6)
	_log("F 按住 Z")
