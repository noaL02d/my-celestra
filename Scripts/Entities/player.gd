extends CharacterBody2D

signal died

const PLAYER_GROUP := "player"

# ═══════════════════════════════════════════════════════
# 状态定义
# ═══════════════════════════════════════════════════════
enum State { NORMAL, DASH, CLIMB, DEAD}

# ═══════════════════════════════════════════════════════
# 参数（Celeste 原值）
# ═══════════════════════════════════════════════════════
@export_group("水平移动")
@export var max_run := 90.0
@export var run_accel := 1000.0
@export var run_reduce := 400.0
@export var air_mult := 0.65
## 空中松开方向键时的水平阻尼（px/s²）。冲刺、加速跳留下的速度也会按它衰减，
## 默认 650 = run_accel(1000) × air_mult(0.65)。调小 = 松手后更飘。
@export var air_drag := 650.0

@export_group("重力")
@export var gravity := 900.0
@export var max_fall := 160.0
@export var fast_max_fall := 240.0
@export var fast_max_accel := 300.0

@export_group("跳跃")
@export var jump_speed := -105.0
@export var jump_h_boost := 40.0
@export var var_jump_time := 0.2
@export var jump_grace_time := 0.1
@export var jump_buffer_time := 0.1

@export_group("冲刺")
@export var dash_speed := 240.0
@export var end_dash_speed := 160.0
@export var end_dash_up_mult := 0.75
@export var dash_time := 0.15
@export var dash_cooldown := 0.2
@export var dash_refill_cooldown := 0.1
@export var max_dashes := 1

@export_group("加速跳 / 凌波微步")
## 冲刺结束后仍能把冲刺速度转成加速跳的时间窗口。
@export var dash_jump_window := 0.15
## 冲刺结束后在这个更短的窗口内起跳，会额外重置一次冲刺次数（凌波微步可据此无限连）。
@export var dash_refill_window := 0.08
## 加速跳时水平速度被拉到的最低值（Celeste 原值 260，普通跑速只有 90）。
@export var super_jump_speed := 260.0
## 加速跳后超速部分的水平阻尼（px/s²）。越小，速度保留越久、跳得越远。
@export var super_speed_reduce := 120.0
## 加速跳后速度保留的持续时间。
@export var super_speed_time := 0.5

@export_group("蹬墙跳强化")
## 强化蹬墙跳的水平速度（Celeste 原值 170，普通蹬墙跳只有 130）。
@export var super_wall_jump_speed := 170.0
## 强化蹬墙跳的竖直速度（Celeste 原值 160，普通跳跃只有 105）。
@export var super_wall_jump_v_speed := 160.0
## 强化蹬墙跳的可变跳跃时长（Celeste 原值 0.25，普通跳跃是 0.2）。
@export var super_wall_jump_var_time := 0.25

@export_group("爬墙")
## 自动攀附：开启后不用按抓墙键，空中贴到墙就会自动抓住；
## 此时抓墙键反过来变成"松手"（输入反转）。关掉则恢复成"按住 Z 才能抓墙"。
@export var auto_climb := true
@export var climb_up_speed := -45.0
@export var climb_down_speed := 80.0
@export var climb_accel := 900.0
@export var climb_max_stamina := 110.0

@export_group("墙滑")
@export var wall_slide_start_max := 20.0
@export var wall_slide_time := 1.2

@export_group("下蹲")
@export var duck_friction := 500.0
@onready var stand_col: CollisionShape2D = $StandCollision
@onready var duck_col: CollisionShape2D = $DuckCollision

@export_group("HUD")
## 是否在角色头顶显示剩余冲刺次数。
@export var show_dash_counter := true

@export_group("音频")
@export var sfx_jump: AudioStream
@export var sfx_dash: AudioStream
@export var sfx_death: AudioStream
@export var sfx_land: AudioStream
@export var sfx_wall_jump: AudioStream
@export var sfx_wall_release: AudioStream
@export var sfx_climb_ledge: AudioStream
@export var sfx_super_jump: AudioStream
@export var sfx_super_wall_jump: AudioStream

# ═══════════════════════════════════════════════════════
# 状态机
# ═══════════════════════════════════════════════════════
var state: State = State.NORMAL
var prev_state: State = State.NORMAL

# ═══════════════════════════════════════════════════════
# 运行时变量
# ═══════════════════════════════════════════════════════
var input_x := 0.0
var input_y := 0.0
var facing := 1
var on_ground := false
var was_on_ground := false

var spawn_point := Vector2.ZERO
var is_dying := false

# 跳跃
var var_jump_timer := 0.0
var var_jump_speed := 0.0
## 狼跳计时器，保证离开地面后一小段时间仍能起跳。
var jump_grace_timer := 0.0
## 跳跃输入缓冲，保证在接触地面前按下跳跃键也能在接触地面的瞬间起跳。
var jump_buffer_timer := 0.0
var auto_jump := false

# 冲刺
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_refill_timer := 0.0
var dash_dir := Vector2.ZERO
var before_dash_speed := Vector2.ZERO
var dashes := 1

# 加速跳 / 凌波微步
## 距离上一次冲刺结束的时间窗口，窗口内起跳可以触发加速跳。
var dash_jump_timer := 0.0
## 更短的窗口，窗口内起跳会额外补满冲刺次数。
var dash_refill_jump_timer := 0.0
## 加速跳后的速度保留计时器。
var super_speed_timer := 0.0
## 最近一次冲刺的方向，用于判断"同向 / 向量分解方向"起跳。
var last_dash_dir := Vector2.ZERO
## 冲刺过程中是否按过跳跃键（按过之后只要还按着，就一直续跳跃缓冲）。
var dash_jump_held := false

# 墙滑
var wall_slide_timer := 0.0
var is_wall_sliding := false

# 爬墙
var stamina := 0.0

# 下落
var current_max_fall := 160.0

# 下蹲
var is_ducking := false

# ═══════════════════════════════════════════════════════
# 开发者模式（由 Scenes/Tools/DevMode.tscn 写入，正常游玩时保持默认值）
# ═══════════════════════════════════════════════════════
@export_group("开发者模式")
## 飞行模式下的移动速度。
@export var fly_speed := 180.0
## 无敌：屏蔽一切死亡，包括 R 键自尽。
var invincible := false
## 飞行：无视重力，直接用方向键移动。
var flying := false
## 无限体力：抓墙不会力竭。
var infinite_stamina := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var dash_counter: Label = $DashCounter

# ═══════════════════════════════════════════════════════
# 主循环
# ═══════════════════════════════════════════════════════
func _ready() -> void:
	spawn_point = global_position
	dashes = max_dashes
	stamina = climb_max_stamina
	current_max_fall = max_fall
	add_to_group(PLAYER_GROUP)

func _physics_process(delta: float) -> void:
	_update_hud()

	if is_dying:
		return

	if Input.is_action_just_pressed("reset"):
		die()
		return;

	on_ground = is_on_floor()
	
	if on_ground and not was_on_ground:
		AudioManager.play_sfx(sfx_land)

	_read_input()
	_update_common_timers(delta)

	# 开发者飞行：跳过状态机与重力，直接按方向键移动
	if flying:
		_apply_fly()
		return

	# 状态分派
	var next := _update_state(delta)
	if next != state:
		_change_state(next)

	move_and_slide()
	_update_sprite()

	was_on_ground = on_ground

# ═══════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════
## 头顶的剩余冲刺次数。
func _update_hud() -> void:
	if dash_counter == null:
		return
	dash_counter.visible = show_dash_counter
	dash_counter.text = str(dashes)
	# 冲刺用光时压暗一点，一眼能看出没得冲了
	dash_counter.modulate = Color.WHITE if dashes > 0 else Color(1.0, 0.55, 0.55, 0.75)

# ═══════════════════════════════════════════════════════
# 公共逻辑
# ═══════════════════════════════════════════════════════
func _read_input() -> void:
	input_x = Input.get_axis("left", "right")
	input_y = Input.get_axis("up", "down")
	if input_x != 0.0:
		facing = int(signf(input_x))
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
		if state == State.DASH:
			dash_jump_held = true

func _update_common_timers(delta: float) -> void:
	jump_grace_timer = maxf(0.0, jump_grace_timer - delta)
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	dash_refill_timer = maxf(0.0, dash_refill_timer - delta)
	dash_jump_timer = maxf(0.0, dash_jump_timer - delta)
	dash_refill_jump_timer = maxf(0.0, dash_refill_jump_timer - delta)
	super_speed_timer = maxf(0.0, super_speed_timer - delta)

	if on_ground:
		jump_grace_timer = jump_grace_time
		wall_slide_timer = wall_slide_time
		stamina = climb_max_stamina
		if dash_refill_timer <= 0.0:
			dashes = max_dashes

	if infinite_stamina:
		stamina = climb_max_stamina

func _change_state(next: State) -> void:
	_state_end(state)
	prev_state = state
	state = next
	_state_begin(state)

func _update_state(delta: float) -> State:
	match state:
		State.NORMAL: return _normal_update(delta)
		State.DASH: return _dash_update(delta)
		State.CLIMB: return _climb_update(delta)
	return state

func _state_begin(s: State) -> void:
	match s:
		State.NORMAL: _normal_begin()
		State.DASH: _dash_begin()
		State.CLIMB: _climb_begin()

func _state_end(s: State) -> void:
	match s:
		State.NORMAL: _normal_end()
		State.DASH: _dash_end()
		State.CLIMB: _climb_end()

# ═══════════════════════════════════════════════════════
# NORMAL 状态
# ═══════════════════════════════════════════════════════
func _normal_begin() -> void:
	current_max_fall = max_fall
	is_wall_sliding = false

func _normal_update(delta: float) -> State:
	if on_ground:
		if Input.is_action_pressed("down") and not is_ducking:
			_set_ducking(true)
		elif not Input.is_action_pressed("down") and is_ducking:
			if _can_un_duck():
				_set_ducking(false)
	
	# 1. 冲刺？
	if _can_dash():
		return State.DASH

	# 2. 抓墙？
	if _can_start_climb():
		return State.CLIMB

	# 3. 跳跃
	if jump_buffer_timer > 0.0:
		if on_ground or jump_grace_timer > 0.0:
			_do_jump()
		elif is_on_wall():
			var wall_dir := _get_wall_dir()
			if wall_dir == 0:
				pass
			elif not auto_climb and Input.is_action_pressed("grab") and stamina > 0.0:
				_do_climb_jump()
			else:
				_do_wall_jump()   

	# 4. 水平移动
	_apply_horizontal(delta)

	# 5. 重力
	_apply_gravity(delta)

	# 6. 可变跳跃（钉住上升速度）
	_apply_var_jump(delta)

	# 7. 墙滑
	_apply_wall_slide(delta)

	return State.NORMAL

func _normal_end() -> void:
	is_wall_sliding = false

# ═══════════════════════════════════════════════════════
# DASH 状态
# ═══════════════════════════════════════════════════════
func _dash_begin() -> void:
	if is_ducking:
		_set_ducking(false)
	AudioManager.play_sfx(sfx_dash)
	var dir := Vector2(input_x, input_y)
	if dir == Vector2.ZERO:
		dir = Vector2(facing, 0)
	dash_dir = dir.normalized()
	last_dash_dir = dash_dir
	dash_jump_timer = dash_jump_window
	dash_jump_held = false

	before_dash_speed = velocity
	velocity = dash_dir * dash_speed

	dash_timer = dash_time
	dash_cooldown_timer = dash_cooldown
	dash_refill_timer = dash_refill_cooldown
	dashes -= 1

	if dash_dir.x != 0.0:
		facing = int(signf(dash_dir.x))

func _dash_update(delta: float) -> State:
	dash_timer -= delta
	velocity = dash_dir * dash_speed   # 冲刺期间完全接管
	# 冲刺全程都在续加速跳窗口，这样"冲刺刚结束就跳"一定生效
	dash_jump_timer = dash_jump_window
	# 冲刺中按下的跳跃键：只要没松手就一直续缓冲，
	# 不会因为 0.1s 缓冲超时而错过冲刺结束的那一瞬间。
	if dash_jump_held and Input.is_action_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	# 斜向下 / 向下冲刺已经贴地 → 立刻结束冲刺。
	# 这是"超冲刺（Hyper）"和"凌波微步"的判定起点：
	# 垂直分量被地面吃掉，只留水平速度用于接下来的加速跳。
	if on_ground and dash_dir.y > 0.0:
		return State.NORMAL

	if dash_timer <= 0.0:
		return State.NORMAL
	return State.DASH

func _dash_end() -> void:
	# 冲刺结束的瞬间开启"极短时间补冲刺"的窗口
	dash_refill_jump_timer = dash_refill_window
	dash_jump_held = false

	# 冲刺结束速度
	velocity = dash_dir * end_dash_speed
	if velocity.y < 0.0:
		velocity.y *= end_dash_up_mult

	# 保留冲刺前水平动量
	if signf(before_dash_speed.x) == signf(velocity.x) \
			and absf(before_dash_speed.x) > absf(velocity.x):
		velocity.x = before_dash_speed.x

# ═══════════════════════════════════════════════════════
# CLIMB 状态
# ═══════════════════════════════════════════════════════
func _climb_begin() -> void:
	if is_ducking:
		_set_ducking(false)
	velocity.x = 0.0
	velocity.y *= 0.2   # 抓墙瞬间 Y 速度衰减
	var wall_dir := _get_wall_dir()
	if wall_dir != 0:
		for i in range(2):
			if move_and_collide(Vector2(wall_dir, 0)):
				break

func _climb_update(delta: float) -> State:
	# 1. 松抓键 → 离开（自动攀附时是"按下抓墙键"才松手）
	if not _grab_held():
		AudioManager.play_sfx(sfx_wall_release)
		return State.NORMAL

	# 1.5 自动攀附时踩到地面 → 自动松手，避免贴在地上一直挂着
	if auto_climb and on_ground:
		return State.NORMAL

	# 2. 跳
	if jump_buffer_timer > 0.0:
		# 这里用不依赖朝向的探测：按住离开墙的方向起跳 → 蹬墙跳，否则贴墙跳
		var jump_wall_dir := _find_wall_dir()
		if jump_wall_dir != 0 and input_x == float(-jump_wall_dir):
			_do_wall_jump(jump_wall_dir)
		else:
			_do_climb_jump()
		return State.NORMAL

	# 3. 冲刺
	if _can_dash():
		return State.DASH

	# 4. 没墙了 → 离开
	var wall_dir := _get_wall_dir()
	if wall_dir == 0:
		return State.NORMAL

	# 5. 爬墙移动
	var target_y := 0.0
	if input_y < 0.0:
		target_y = climb_up_speed
		stamina -= 45.0 * delta      # 向上爬消耗
	elif input_y > 0.0:
		target_y = climb_down_speed
	else:
		stamina -= 10.0 * delta      # 静止挂消耗

	velocity.y = move_toward(velocity.y, target_y, climb_accel * delta)
	velocity.x = 0.0

	# 6. 体力耗尽 → 离开
	if stamina <= 0.0:
		return State.NORMAL

	return State.CLIMB

func _climb_end() -> void:
	pass

# ═══════════════════════════════════════════════════════
# 辅助判断
# ═══════════════════════════════════════════════════════

## 玩家是否有意图且能够完成一次冲刺。只在玩家按下冲刺键，且当前能够冲刺时返回true。
func _can_dash() -> bool:
	return Input.is_action_just_pressed("dash") \
		and dashes > 0 \
		and dash_cooldown_timer <= 0.0

func _can_start_climb() -> bool:
	if not _grab_held(): return false
	if auto_climb and on_ground: return false   # 站在地上时不要自动粘住旁边的墙
	if stamina <= 0.0: return false
	if velocity.y < 0.0: return false   # 上升时不能抓
	return _get_wall_dir() != 0

## 是否处于"抓住墙壁"的输入状态。
## 自动攀附开启时逻辑反转：默认视为一直按着抓墙键，按 grab 键反而变成"松手"。
func _grab_held() -> bool:
	if auto_climb:
		return not Input.is_action_pressed("grab")
	return Input.is_action_pressed("grab")

## 当前朝向那一侧的墙的方向。返回 facing 或 0。
func _get_wall_dir() -> int:
	return _probe_wall(facing)

## 不依赖朝向：先看面前，再看背后，返回任意一侧的墙的方向。用于"从墙上跳走"。
func _find_wall_dir() -> int:
	var dir := _probe_wall(facing)
	if dir != 0:
		return dir
	return _probe_wall(-facing)

## 朝指定方向探测墙，探到就返回 dir，否则返回 0。
func _probe_wall(dir: int) -> int:
	if dir == 0:
		return 0
	var space := get_world_2d().direct_space_state
	var origin := global_position + Vector2(0, -5.5)   # 玩家中心
	var probe := 6.0                                    # 探测距离（像素）

	var query := PhysicsRayQueryParameters2D.create(
		origin,
		origin + Vector2(dir * probe, 0)
	)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	if space.intersect_ray(query):
		return dir   # 墙在 dir 方向

	return 0
	
func _can_un_duck() -> bool:
	if not is_ducking:
		return true
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = stand_col.shape
	query.transform = stand_col.global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var result := space.intersect_shape(query, 1)
	return result.is_empty()

# ═══════════════════════════════════════════════════════
# 动作
# ═══════════════════════════════════════════════════════
func _do_jump() -> void:
	jump_buffer_timer = 0.0
	jump_grace_timer = 0.0

	# 起跳时解除蹲伏，避免带着蹲伏碰撞箱起跳。
	# 超冲刺（按住下键冲刺再跳）能成立，也依赖这一步。
	if is_ducking and _can_un_duck():
		_set_ducking(false)

	if _can_super_jump():
		_do_super_jump()
		return

	AudioManager.play_sfx(sfx_jump)
	var_jump_timer = var_jump_time
	var_jump_speed = jump_speed
	velocity.y = jump_speed
	velocity.x += jump_h_boost * input_x

## 本次跳跃是否应该变成"加速跳"。
## 条件：处于冲刺后的窗口内、最近一次冲刺带水平分量、且仍保有冲刺带来的高速。
## 起跳方向不做限制：按住同向是加速跳，按住反向就是"反凌波"。
func _can_super_jump() -> bool:
	if dash_jump_timer <= 0.0:
		return false
	if last_dash_dir.x == 0.0:
		return false                              # 纯竖直冲刺没有水平速度可转
	if absf(velocity.x) <= max_run * 0.5:
		return false
	return true

## 加速跳：保留冲刺的高速，并（在极短窗口内）重置冲刺次数。
func _do_super_jump() -> void:
	var dir := signf(velocity.x)
	# 反凌波：按住反方向起跳时，把冲刺速度整个翻到起跳方向上
	if input_x != 0.0:
		dir = signf(input_x)
	# 水平速度不低于 super_jump_speed；已经更快就保留更快的那个
	velocity.x = dir * maxf(absf(velocity.x), super_jump_speed)
	velocity.y = jump_speed
	var_jump_timer = var_jump_time
	var_jump_speed = jump_speed

	# 凌波微步：冲刺结束后极短时间内起跳 → 白送一次冲刺，可以无限连
	if dash_refill_jump_timer > 0.0:
		dashes = max_dashes
		dash_cooldown_timer = 0.0

	dash_jump_timer = 0.0
	dash_refill_jump_timer = 0.0
	super_speed_timer = super_speed_time

	AudioManager.play_sfx(sfx_super_jump if sfx_super_jump != null else sfx_jump)

## 当前是否处于"保留冲刺速度"的阶段：冲刺刚结束，或刚做完加速跳。
func _is_keeping_speed() -> bool:
	return dash_jump_timer > 0.0 or super_speed_timer > 0.0

## wall_dir 传入 0 时自动按朝向探测（普通情况）。
func _do_wall_jump(wall_dir := 0) -> void:
	if wall_dir == 0:
		wall_dir = _get_wall_dir()
	if wall_dir == 0: return

	# 向上 / 斜向上冲刺后的蹬墙跳 → 强化蹬墙跳
	if _can_super_wall_jump():
		_do_super_wall_jump(wall_dir)
		return

	AudioManager.play_sfx(sfx_wall_jump)
	jump_buffer_timer = 0.0
	var_jump_timer = var_jump_time
	var_jump_speed = jump_speed
	velocity.x = -wall_dir * (max_run + jump_h_boost)
	velocity.y = jump_speed

## 这次蹬墙跳能否吃到冲刺速度。需要：处于冲刺后的窗口内，且最近一次冲刺朝上 / 斜上方。
func _can_super_wall_jump() -> bool:
	if dash_jump_timer <= 0.0:
		return false
	return last_dash_dir.y < 0.0

## 强化蹬墙跳：把向上冲刺的速度转成一次又高又远的蹬墙跳。
## 和凌波微步的区别：它不会补充冲刺次数。
func _do_super_wall_jump(wall_dir: int) -> void:
	AudioManager.play_sfx(
		sfx_super_wall_jump if sfx_super_wall_jump != null else sfx_wall_jump)

	# 竖直：至少给到 super_wall_jump_v_speed，冲刺剩下的上冲速度更快就带上它
	var up_speed := super_wall_jump_v_speed
	if velocity.y < 0.0:
		up_speed = maxf(up_speed, absf(velocity.y))

	jump_buffer_timer = 0.0
	jump_grace_timer = 0.0
	var_jump_timer = super_wall_jump_var_time
	var_jump_speed = -up_speed
	velocity.y = -up_speed
	velocity.x = -wall_dir * super_wall_jump_speed

	dash_jump_timer = 0.0          # 消耗掉强化窗口，避免一次冲刺吃两次
	super_speed_timer = super_speed_time
	# 注意：这里不动 dashes，所以强化蹬墙跳不会恢复冲刺次数

func _do_climb_jump() -> void:
	if not on_ground:
		stamina = maxf(0.0, stamina - 27.5)
	jump_buffer_timer = 0.0
	jump_grace_timer = 0.0
	var_jump_timer = var_jump_time
	var_jump_speed = jump_speed
	velocity.y = jump_speed
	AudioManager.play_sfx(sfx_jump)
	
## 通过此函数设定蹲伏状态，否则不能切换碰撞箱。
func _set_ducking(value: bool) -> void:
	if is_ducking == value:
		return
	is_ducking = value
	stand_col.disabled = value
	duck_col.disabled = not value

# ═══════════════════════════════════════════════════════
# 物理
# ═══════════════════════════════════════════════════════
func _apply_horizontal(delta: float) -> void:
	if is_ducking and is_on_floor() and not _is_keeping_speed():
		velocity.x = move_toward(velocity.x, 0.0, duck_friction * delta)
		return
	
	# 空中松开方向键 → 施加水平阻尼。
	# 没有这一条的话，冲刺 / 加速跳留下的速度会几乎不衰减地一直飘。
	if input_x == 0.0 and not on_ground:
		velocity.x = move_toward(velocity.x, 0.0, air_drag * delta)
		return

	var target := input_x * max_run
	var accel := run_accel
	if not on_ground:
		accel *= air_mult

	# 冲刺 / 加速跳留下的超速：换成很小的阻尼慢慢回落到 max_run。
	# 否则 run_accel（1000）会在几帧内把速度抹平，加速跳就飞不远了。
	if _is_keeping_speed() and absf(velocity.x) > max_run \
			and (input_x == 0.0 or signf(input_x) == signf(velocity.x)):
		var preserve := super_speed_reduce
		if not on_ground:
			preserve *= air_mult
		velocity.x = move_toward(velocity.x, signf(velocity.x) * max_run, preserve * delta)
		return

	if absf(velocity.x) > absf(target) and signf(velocity.x) == signf(target):
		velocity.x = move_toward(velocity.x, target, run_reduce * delta)
	else:
		velocity.x = move_toward(velocity.x, target, accel * delta)

func _apply_gravity(delta: float) -> void:
	if on_ground:
		return
		
	var fast_falling := input_y > 0.5 and velocity.y >= max_fall
	var target_max_fall := fast_max_fall if fast_falling else max_fall
	current_max_fall = move_toward(current_max_fall, target_max_fall, fast_max_accel * delta)
	
	velocity.y += gravity * delta
	velocity.y = minf(velocity.y, current_max_fall)

## 可变跳跃高度。在玩家按住跳跃键时维持当前跳跃的向上速度var_jump_speed，直到松开跳跃键或var_jump_timer计时器归零。
func _apply_var_jump(delta: float) -> void:
	if var_jump_timer <= 0.0:
		return
	var_jump_timer -= delta
	if Input.is_action_pressed("jump") or auto_jump:
		velocity.y = minf(velocity.y, var_jump_speed)
	else:
		var_jump_timer = 0.0

func _apply_wall_slide(delta: float) -> void:
	is_wall_sliding = false

	if on_ground: return
	if velocity.y <= 0.0: return
	if wall_slide_timer <= 0.0: return

	var wall_dir := _get_wall_dir()
	if wall_dir == 0: return
	if input_x != float(wall_dir): return   # 必须朝墙推

	# 墙滑限制下落速度
	var t := wall_slide_timer / wall_slide_time
	var limit := lerpf(max_fall, wall_slide_start_max, t)
	velocity.y = minf(velocity.y, limit)

	wall_slide_timer = maxf(0.0, wall_slide_timer - delta)
	is_wall_sliding = true

## 开发者飞行：忽略重力与状态机，直接用方向键做八向移动。
func _apply_fly() -> void:
	if state != State.NORMAL:
		_change_state(State.NORMAL)
	velocity = Vector2(input_x, input_y).normalized() * fly_speed
	move_and_slide()
	on_ground = is_on_floor()
	_update_sprite()
	was_on_ground = on_ground

func die() -> void:
	if is_dying or invincible:
		return
	is_dying = true
	died.emit()
	AudioManager.play_sfx(sfx_death)
	
	sprite.play("death")
	await sprite.animation_finished
	
	global_position = spawn_point
	velocity = Vector2.ZERO
	state = State.NORMAL
	_set_ducking(false)
	var_jump_timer = 0.0
	dash_timer = 0.0
	jump_buffer_timer = 0.0
	stamina = climb_max_stamina
	dashes = max_dashes
	dash_jump_timer = 0.0
	dash_refill_jump_timer = 0.0
	super_speed_timer = 0.0
	last_dash_dir = Vector2.ZERO
	dash_jump_held = false

	await get_tree().physics_frame
	await get_tree().physics_frame
	is_dying = false
	
func set_spawn_point(pos: Vector2) -> void:
	spawn_point = pos

## 开发者模式的瞬移：清掉速度与残留状态，避免把冲刺/跳跃动量带到目标点。
func teleport_to(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	var_jump_timer = 0.0
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	jump_buffer_timer = 0.0
	if state != State.NORMAL:
		_change_state(State.NORMAL)
	was_on_ground = false

# ═══════════════════════════════════════════════════════
# 动画
# ═══════════════════════════════════════════════════════
func _update_sprite() -> void:
	if input_x != 0.0 and state != State.CLIMB:
		sprite.flip_h = input_x < 0.0

	match state:
		State.DASH:
			sprite.animation = "dash"
		State.CLIMB:
			sprite.animation = "climb"
		State.NORMAL:
			if is_ducking:
				sprite.animation = "duck"
			elif is_wall_sliding:
				sprite.animation = "fall"
			elif not on_ground:
				sprite.animation = "jump" if velocity.y < 0.0 else "fall"
			elif input_x != 0.0:
				sprite.animation = "run"
			else:
				sprite.animation = "idle"
