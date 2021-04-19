extends KinematicBody2D

const fps_mod = 32.0 / 60.0 #Multiplier to account for 60fps
const grav = fps_mod

const set_jump_1_tp = 3
const set_jump_2_tp = set_jump_1_tp * 1.25
const set_jump_3_tp = set_jump_1_tp * 1.5
const set_air_speed_cap = 20.0*fps_mod
const set_walk_accel = 1.2 * fps_mod
const set_air_accel = 5.0 * fps_mod #Functions differently to walkAccel
const set_walk_decel = set_walk_accel * 1.1 #Suggested by Maker - decel is faster than accel in casual mode
const set_air_decel = set_air_accel * 1.1
const set_jump_1_vel = 10 * fps_mod
const set_jump_2_vel = set_jump_1_vel + 2.5 * fps_mod
const set_jump_3_vel = set_jump_1_vel + 5.0 * fps_mod
var set_wall_bounce
const set_jump_mod_frames = 13
const set_double_jump_frames = 17
const set_triple_jump_deadzone = 3.0 * fps_mod
const set_dive_speed = 35.0 * fps_mod
const set_dive_correct = 7
const set_hover_speed = 9.2

onready var voice = $Voice
onready var tween = $Tween
onready var sprite = $AnimatedSprite
onready var camera = $Camera2D
onready var angle_cast = $DiveAngling

#mario's gameplay parameters
export var life_meter_counter = 8
export var water = 100
export var power = 100
export var fludd_strain = false
var static_v = false #for pipe, may be used for other things.
#####################

const voice_bank = {
	"jump1": [
		preload("res://audio/sfx/mario/jump1/ya1.wav"),
		preload("res://audio/sfx/mario/jump1/ya2.wav"),
		preload("res://audio/sfx/mario/jump1/ya3.wav"),
	],
	"jump2": [
		preload("res://audio/sfx/mario/jump2/ma1.wav"),
		preload("res://audio/sfx/mario/jump2/ma2.wav"),
		preload("res://audio/sfx/mario/jump2/ma3.wav"),
	],
	"jump3": [
		preload("res://audio/sfx/mario/jump3/wahoo1.wav"),
		preload("res://audio/sfx/mario/jump3/wahoo2.wav"),
		preload("res://audio/sfx/mario/jump3/wahoo3.wav"),
		preload("res://audio/sfx/mario/jump3/wahoo4.wav"),
		preload("res://audio/sfx/mario/jump3/wahoo5.wav"),
	],
	"dive": [
		preload("res://audio/sfx/mario/dive/wa1.wav"),
		preload("res://audio/sfx/mario/dive/wa2.wav"),
		preload("res://audio/sfx/mario/dive/wa3.wav"),
	],
}

var jump_frames = -1
var vel = Vector2()
var double_jump_state = 0
var double_jump_frames = 0
var spin_timer = 0
var flip_l
var dive_return = false
var dive_frames = 0
var pound_frames = 0
var rocket_charge = 0

var maxY = 0

enum s { #state enum
	walk,
	frontflip,
	backflip,
	spin,
	dive,
	diveflip,
	pound_spin,
	pound_fall,
	pound_land,
	door,
}

enum n { #fludd enum
	none,
	hover,
	rocket,
	turbo,
}

var state = s.walk
var nozzle = n.rocket
var classic

func dive_correct(factor): #Correct the player's origin position when diving
	#warning-ignore:return_value_discarded
	move_and_slide(Vector2(0, set_dive_correct * factor * 60), Vector2(0, -1))
	camera.position.y = min(0, -set_dive_correct * factor)

func screen_handling():
	if Input.is_action_just_pressed("fullscreen"):
		OS.window_fullscreen = !OS.window_fullscreen
	if Input.is_action_just_pressed("screen+") && OS.window_size.x * 2 <= OS.get_screen_size().x && OS.window_size.y * 2 <= OS.get_screen_size().y:
		OS.window_size *= 2
		$Camera2D/GUI.scale *= 2
	if Input.is_action_just_pressed("screen-") && OS.window_size.x / 2 >= 448:
		OS.window_size /= 2
		$Camera2D/GUI.scale /= 2
	var zoom_factor = 448/OS.window_size.x
	camera.zoom = Vector2(zoom_factor, zoom_factor)

func play_voice(group_name):
	var group = voice_bank[group_name]
	var sound = group[randi() % group.size()]
	voice.stream = sound
	voice.play(0)

func update_classic():
	classic = $"/root/Main".classic #this isn't a filename don't change Main to lowercase lol
	if classic:
		set_wall_bounce = 0.5
	else:
		set_wall_bounce = 0.19

func switch_anim(new_anim):
	var fludd_anim
	match nozzle:
		n.hover:
			fludd_anim = "hover_" + new_anim
			if sprite.frames.has_animation(fludd_anim):
				sprite.animation = fludd_anim
			else:
				sprite.animation = new_anim
		n.rocket:
			fludd_anim = "rocket_" + new_anim
			if sprite.frames.has_animation(fludd_anim):
				sprite.animation = fludd_anim
			else:
				sprite.animation = new_anim
		n.turbo:
			fludd_anim = "turbo_" + new_anim
			if sprite.frames.has_animation(fludd_anim):
				sprite.animation = fludd_anim
			else:
				sprite.animation = new_anim
		_:
			sprite.animation = new_anim

func switch_state(new_state):
	state = new_state
	sprite.rotation_degrees = 0
	match state:
		s.dive:
			$StandHitbox.disabled = true
			$DiveHitbox.disabled = false
		s.pound_fall:
			$StandHitbox.disabled = false
			$DiveHitbox.disabled = true
			camera.smoothing_speed = 10
		_:
			$StandHitbox.disabled = false
			$DiveHitbox.disabled = true
			camera.smoothing_speed = 5

func _ready():
	update_classic()

func ground_friction(val, sub, div): #Ripped from source
	val = val/fps_mod
	var vel_sign = sign(val)
	val = abs(val)
	val -= sub
	val = max(0, val)
	val /= div
	val *= vel_sign
	return val*fps_mod

func _physics_process(_delta):
	if !static_v: #for the pipe, maybe will be used for other things.
		var i_left = Input.is_action_pressed("left")
		var i_right = Input.is_action_pressed("right")
		var i_down = Input.is_action_pressed("down")
		var i_jump = Input.is_action_just_pressed("jump")
		var i_jump_h = Input.is_action_pressed("jump")
		var i_dive = Input.is_action_just_pressed("dive")
		var i_dive_h = Input.is_action_pressed("dive")
		var i_spin = Input.is_action_just_pressed("spin")
		var i_spin_h = Input.is_action_pressed("spin")
		var i_pound_h = Input.is_action_pressed("pound")
		var i_fludd = Input.is_action_pressed("fludd")
		var i_switch = Input.is_action_just_pressed("switch_fludd")
		var test = 0
		if (Input.is_action_just_pressed("debug")):
			if i_jump_h:
				#warning-ignore:return_value_discarded
				#get_tree().change_scene("res://level_designer.tscn")
				get_tree().change_scene("res://scenes/tutorial_1/tutorial_1_1.tscn")
				#get_tree().change_scene("res://scenes/castle/lobby/castle_lobby.tscn")
			else:
				$"/root/Main".classic = !classic
				update_classic()
		var ground = is_on_floor()
		var wall = is_on_wall()
		var ceiling = is_on_ceiling()
		
		if i_switch:
			nozzle = (nozzle + 1) % 4
		
		var fall_adjust = vel.y #Used to adjust downward acceleration to account for framerate difference
		if state == s.diveflip:
			if flip_l:
				sprite.rotation_degrees -= 20
			else:
				sprite.rotation_degrees += 20
			if abs(sprite.rotation_degrees) > 360-20 || ground:
				switch_state(s.walk)
				sprite.rotation_degrees = 0
		elif dive_return:
			dive_frames -= 1
			if dive_frames == 0:
				switch_anim("jump")
				sprite.rotation_degrees += -90 if sprite.flip_h else 90
				dive_correct(-1)
				$StandHitbox.disabled = false
				$DiveHitbox.disabled = true
				
			if sprite.rotation_degrees != 0 || dive_frames > 2:
				sprite.rotation_degrees += 10 if sprite.flip_h else -10
			else:
				dive_return = false
				switch_state(s.walk)
				sprite.rotation_degrees = 0
			
		if ground:
			if state == s.pound_fall:
				pound_frames = max(0, pound_frames - 1)
				if pound_frames <= 0:
					switch_state(s.walk)
			fall_adjust = 0
			if state == s.dive:
				vel.x = ground_friction(vel.x, 0.2, 1.05) #Floor friction
				if angle_cast.is_colliding() && !dive_return:
					#var diff = fmod(angle_cast.get_collision_normal().angle() + PI/2 - sprite.rotation, PI * 2)
					sprite.rotation = lerp_angle(sprite.rotation, angle_cast.get_collision_normal().angle() + PI/2, 0.5)
			else:
				vel.x = ground_friction(vel.x, 0.3, 1.15) #Floor friction
			
			if state == s.frontflip || state == s.backflip: #Reset state when landing
				switch_state(s.walk)
				sprite.rotation_degrees = 0
				tween.stop_all()
			
			if state == s.dive && abs(vel.x) == 0 && !i_dive_h && !dive_return:
				dive_return = true
				dive_frames = 4
				sprite.rotation_degrees = 0
			if state == s.walk:
				switch_anim("walk")
			
			double_jump_frames = max(double_jump_frames - 1, 0)
			if double_jump_frames <= 0:
				double_jump_state = 0
		else:
			if state == s.frontflip:
				switch_anim("flip")
			elif state == s.walk:
				if vel.y > 0:
					switch_anim("fall")
				else:
					switch_anim("jump")
			elif state == s.pound_fall:
				switch_anim("pound_fall")
			elif state == s.dive:
				if sprite.flip_h:
					sprite.rotation = lerp_angle(sprite.rotation, -atan2(vel.y, -vel.x), 0.5)
				else:
					sprite.rotation = lerp_angle(sprite.rotation, atan2(vel.y, vel.x), 0.5)
			
			if i_left == i_right:
				vel.x = ground_friction(vel.x, 0, 1.001) #Air decel

		if state == s.pound_spin:
			vel *= 0
		else:
			if state == s.pound_fall:
				fall_adjust += 0.814
			else:
				fall_adjust += grav
			
			if !ground:
				if state == s.pound_fall:
					pound_frames = 15
				if fall_adjust > 0:
					fall_adjust = ground_friction(fall_adjust, ((grav/fps_mod)/5), 1.05)
				fall_adjust = ground_friction(fall_adjust, 0, 1.001)
				if state == s.spin && !i_down:
					#fall_adjust = ground_friction(fall_adjust, 0.3, 1.05) #fastspin
					fall_adjust = ground_friction(fall_adjust, 0.1, 1.03)
				vel.x = ground_friction(vel.x, 0, 1.001) #Air friction
				
				jump_frames = max(jump_frames - 1, -1)
				
			vel.y += (fall_adjust - vel.y) * fps_mod #Adjust the Y velocity according to the framerate
		
		if i_jump_h:
			if ground:
				if state == s.dive:
					if ((int(i_right) - int(i_left) != -1) && !sprite.flip_h) || ((int(i_right) - int(i_left) != 1) && sprite.flip_h):
						if !dive_return:
							dive_correct(-1)
							switch_state(s.diveflip)
							vel.y = min(-set_jump_1_vel/1.5, vel.y)
							switch_anim("jump")
							flip_l = sprite.flip_h
					else:
						dive_correct(-1)
						switch_state(s.backflip)
						vel.y = min(-set_jump_1_vel - 2.0 * fps_mod, vel.y)
						if sprite.flip_h:
							vel.x += (30.0 - abs(vel.x)) / (5 / fps_mod)
						else:
							vel.x -= (30.0 - abs(vel.x)) / (5 / fps_mod)
						dive_return = false
						tween.stop_all()
						if sprite.flip_h:
							tween.interpolate_property(sprite, "rotation_degrees", 0, 360, 0.6, 1, Tween.EASE_OUT, 0)
						else:
							tween.interpolate_property(sprite, "rotation_degrees", 0, -360, 0.6, 1, Tween.EASE_OUT, 0)
						tween.start()
						switch_anim("jump")
						flip_l = sprite.flip_h
					
					
				elif i_jump && state != s.pound_fall:
					jump_frames = set_jump_mod_frames
					double_jump_frames = set_double_jump_frames
					
					match double_jump_state:
						0: #Single
							switch_state(s.walk)
							play_voice("jump1")
							vel.y = -set_jump_1_vel
							double_jump_state+=1
						1: #Double
							switch_state(s.walk)
							play_voice("jump2")
							vel.y = -set_jump_2_vel
							double_jump_state+=1
						2: #Triple
							if abs(vel.x) > set_triple_jump_deadzone:
								vel.y = -set_jump_3_vel
								vel.x += (vel.x + 15*fps_mod*sign(vel.x))/5*fps_mod
								double_jump_state = 0
								switch_state(s.frontflip)
								play_voice("jump3") 
								if nozzle == n.none:
									tween.interpolate_property(sprite, "rotation_degrees", 0, -720 if sprite.flip_h else 720, 1, Tween.TRANS_QUART, Tween.EASE_OUT)
								else:
									tween.interpolate_property(sprite, "rotation_degrees", 0, -360 if sprite.flip_h else 360, 1, Tween.TRANS_QUART, Tween.EASE_OUT)
								tween.start()
								flip_l = sprite.flip_h
							else:
								vel.y = -set_jump_2_vel #Not moving left/right fast enough
								play_voice("jump2")
					
					if !classic:
						#warning-ignore:return_value_discarded
						move_and_collide(Vector2(0, -set_jump_1_tp)) #Suggested by Maker - slight upwards teleport
			elif jump_frames > 0 && state == s.walk:
				vel.y -= grav * pow(fps_mod, 3) #Variable jump height
		
		if i_left && !i_right && state != s.pound_spin:
			if (state != s.dive
			&& (state != s.diveflip || !classic)
			&& (state != s.frontflip || !classic)
			&& state != s.backflip
			&& state != s.pound_fall
			):
				sprite.flip_h = true
			if ground:
				if state != s.dive && state != s.pound_fall:
					vel.x -= set_walk_accel
			else:
				if state == s.pound_fall:
					vel.x *= 0.95
				if state == s.frontflip || state == s.spin || state == s.backflip:
					vel.x -= max((set_air_accel+vel.x)/(set_air_speed_cap/(3*fps_mod)), 0) / (1.5 / fps_mod)
				elif state == s.dive || state == s.diveflip:
					vel.x -= max((set_air_accel+vel.x)/(set_air_speed_cap/(3*fps_mod)), 0) / (8 / fps_mod)
				else:
					vel.x -= max((set_air_accel+vel.x)/(set_air_speed_cap/(3*fps_mod)), 0)
				
		if i_right && !i_left && state != s.pound_spin:
			if (state != s.dive
			&& (state != s.diveflip || !classic)
			&& (state != s.frontflip || !classic)
			&& state != s.backflip
			&& state != s.pound_fall
			):
				sprite.flip_h = false
			if ground:
				if state != s.dive && state != s.pound_fall:
					vel.x += set_walk_accel
			else:
				if state == s.frontflip || state == s.spin || state == s.backflip:
					vel.x += max((set_air_accel-vel.x)/(set_air_speed_cap/(3*fps_mod)), 0) / (1.5 / fps_mod)
				elif state == s.dive || state == s.diveflip:
					vel.x += max((set_air_accel-vel.x)/(set_air_speed_cap/(3*fps_mod)), 0) / (8 / fps_mod)
				else:
					vel.x += max((set_air_accel-vel.x)/(set_air_speed_cap/(3*fps_mod)), 0)
		
		if i_fludd && power > 0 && water > 0 && state != s.diveflip && state != s.spin && state != s.pound_spin && state != s.pound_fall && state != s.pound_land:
			match nozzle:
				n.hover:
					fludd_strain = true
					if classic || state != s.frontflip || (abs(sprite.rotation_degrees) < 90 || abs(sprite.rotation_degrees) > 270):
						if state == s.dive || state == s.frontflip:
							vel.y *= 1 - 0.02 * fps_mod
							vel.x *= 1 - 0.03 * fps_mod
							if ground:
								vel.x += cos(sprite.rotation)*0.92*pow(fps_mod, 2) * (-1 if sprite.flip_h else 1)
							elif state == s.dive:
								vel.y += sin(sprite.rotation * (-1 if sprite.flip_h else 1))*0.92*pow(fps_mod, 2)
								vel.x += cos(sprite.rotation)*0.92/2*pow(fps_mod, 2) * (-1 if sprite.flip_h else 1)
							else:
								if sprite.flip_h:
									vel.y += sin(-sprite.rotation - PI / 2)*0.92*pow(fps_mod, 2)
									vel.x -= cos(-sprite.rotation - PI / 2)*0.92/2*pow(fps_mod, 2)
								else:
									vel.y += sin(sprite.rotation - PI / 2)*0.92*pow(fps_mod, 2)
									vel.x += cos(sprite.rotation - PI / 2)*0.92/2*pow(fps_mod, 2)
						else:
							if power == 100:
								vel.y -= 2
							
							if i_jump_h:
								vel.y *= 1 - (0.12 * fps_mod)
							else:
								vel.y *= 1 - (0.2 * fps_mod)
							#vel.y -= (((9.2 * fps_mod)-vel.y * fps_mod)/(10 / fps_mod))*((power/(175 / fps_mod))+(0.75 * fps_mod))
							#vel.y -= (((9.2 * fps_mod)-vel.y * fps_mod)/10)*((power/(175))+(0.75 * fps_mod))
							vel.y -= (((-4*power*vel.y * fps_mod * fps_mod) + (-525*vel.y * fps_mod) + (368*power * fps_mod * fps_mod) + (48300)) / 7000) * pow(fps_mod, 5)
							vel.x = ground_friction(vel.x, 0.05, 1.03)
						water = max(0, water - 0.07 * fps_mod)
						power -= 1.5 * fps_mod
				n.rocket:
					if power == 100:
						fludd_strain = true
						rocket_charge += 1
					if rocket_charge >= 14 / fps_mod && (state != s.frontflip || (round(abs(sprite.rotation_degrees)) < 2 || round(abs(sprite.rotation_degrees)) > 358) || (!classic && (abs(sprite.rotation_degrees) < 20 || abs(sprite.rotation_degrees) > 340))):
						if state == s.dive:
							vel -= Vector2(-cos(sprite.rotation)*25*fps_mod * -fps_mod if sprite.flip_h else fps_mod, sin(sprite.rotation - PI / 2)*25*fps_mod * fps_mod)
	#					elif state == s.frontflip:
	#						vel -= Vector2(-cos(sprite.rotation - PI / 2)*25*fps_mod, sin(sprite.rotation + PI / 2)*25*fps_mod)
						else:
							vel.y = min(max((vel.y/3),0) - 15.3, vel.y)
							vel.y -= 0.5 * fps_mod
						
						water = max(water - 5, 0)
						rocket_charge = 0
						power = 0
		else:
			fludd_strain = false
			rocket_charge = 0
			if ground:
				power = 100
			elif !i_fludd && nozzle != n.hover:
				power = min(power + fps_mod, 100)
		
		if i_dive_h && state != s.dive && (state != s.diveflip || (!classic && i_dive && sprite.flip_h != flip_l)) && state != s.pound_spin && (state != s.spin || (!classic && i_dive)): #dive
			if ground && i_jump_h:
				dive_correct(-1)
				switch_state(s.diveflip)
				switch_anim("jump")
				flip_l = sprite.flip_h
				vel.y = min(-set_jump_1_vel/1.5, vel.y)
				double_jump_state = 0
			elif ((state != s.backflip || abs(sprite.rotation_degrees) > 270)
				&& state != s.pound_fall
				&& state != s.pound_spin):
				switch_state(s.dive)
				rotation_degrees = 0
				tween.stop_all()
				switch_anim("dive")
				double_jump_state = 0
				dive_correct(1)
				if !ground:
					play_voice("dive")
					if sprite.flip_h:
						vel.x -= (set_dive_speed - abs(vel.x)) / (5 / fps_mod) / fps_mod * 0.75
					else:
						vel.x += (set_dive_speed - abs(vel.x)) / (5 / fps_mod) / fps_mod * 0.75
					vel.y += 3.0 * fps_mod
		
		if state == s.spin:
			if spin_timer > 0:
				spin_timer -= 1
			elif !i_spin_h:
				switch_state(s.walk)
		
		if (i_spin_h
		&& state != s.spin
		&& state != s.frontflip
		&& state != s.dive
		&& (state != s.diveflip || (!classic && i_spin))
		&& (vel.y > -3.3 * fps_mod || (!classic && state == s.diveflip))
		&& state != s.pound_fall
		&& state != s.pound_spin):
			switch_state(s.spin)
			switch_anim("spin")
			vel.y = min(-3.3 * fps_mod, vel.y - 3.3 * fps_mod)
			spin_timer = 30
		
		if i_pound_h && !ground && state != s.pound_spin && state != s.pound_fall && (state != s.dive || !classic) && (state != s.diveflip || !classic) && (state != s.spin || !classic):
			switch_state(s.pound_spin)
			tween.interpolate_property(sprite, "rotation_degrees", 0, -360 if sprite.flip_h else 360, 0.25)
			tween.start()
		
		if wall:
			if int(i_right) - int(i_left) != sign(int(vel.x)) && int(vel.x) != 0:
				vel.x = -vel.x*set_wall_bounce #Bounce off a wall when not intentionally pushing into it
			else:
				vel.x = 0 #Cancel X velocity when intentionally pushing into a wall
				
		if ceiling:
			vel.y = max(vel.y, 0.1)
		
		var snap
		if !ground || i_jump || state == s.diveflip || i_fludd:
			snap = Vector2.ZERO
		else:
			snap = Vector2(0, 4)
			
		var save_pos = position
		#warning-ignore:return_value_discarded
		move_and_slide_with_snap(vel*60, snap, Vector2(0, -1), true)
		var slide_vec = position-save_pos
		position = save_pos
		if slide_vec.length() > 0.5:
			#warning-ignore:return_value_discarded
			move_and_slide_with_snap(vel*60 * (vel.length()/slide_vec.length()), snap, Vector2(0, -1), true)
		
		maxY = max(vel.y, maxY)
		$Label.text = String(test)

		screen_handling()

func _on_Tween_tween_completed(_object, _key):
	if state == s.pound_spin:
		switch_state(s.pound_fall)
		vel.y = 8
	else:
		switch_state(s.walk)
