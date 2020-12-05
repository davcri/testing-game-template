extends Node

signal change_started
signal change_finished

# scenes which are prevented to be loaded.
# `fallback_scene` will be loaded instead.
const scenes_denylist = [
	"res://scenes/main.tscn"
]
const fallback_scene = "res://scenes/menu/menu.tscn"
const minimum_transition_duration = 500 #ms

var main: Main
var loader: ResourceInteractiveLoader
var time_max = 400 # msec
var loading_start_time = 0
var _params = {}

onready var resource_multithread_loader = preload("res://autoload/scenes/resource_multithread_loader.gd").new()
var scene_to_load


func _ready():
	add_child(resource_multithread_loader)

	if main == null:
		call_deferred("_force_load")
	pause_mode = Node.PAUSE_MODE_PROCESS


func _set_main_node(node: Main):
	main = node


func _force_load():
	""" Needed when starting a specific scene with Play Scene with F6,
	instead of starting the game from main.tscn"""
	var played_scene = get_tree().current_scene
	var root = get_node("/root")
	main = load("res://scenes/main.tscn").instance()
	main.initial_fade_active = false
	root.remove_child(played_scene)
	root.add_child(main)
	main.active_scene_container.get_child(0).queue_free()
	main.active_scene_container.add_child(played_scene)
	if played_scene.has_method("pre_start"):
		played_scene.pre_start({})
	if played_scene.has_method("start"):
		played_scene.start()
	played_scene.owner = main


func _change_scene_background_loading(new_scene: String, params = {}):
	loader = ResourceLoader.load_interactive(new_scene)
	if loader == null: # Check for errors.
		print("Error while initializing ResourceLoader")
		return
	emit_signal("change_started")
	_params = params
	loading_start_time = OS.get_ticks_msec()
	var transitions: Transitions = main.transitions
	transitions.fade_in()
	yield(transitions.anim, "animation_finished")
	set_process(true)


func _process(delta: float) -> void:
	if loader == null:
		set_process(false)
		return
	var t = OS.get_ticks_msec()
	# Use "time_max" to control for how long we block this thread.
	while OS.get_ticks_msec() < t + time_max:
		var err = loader.poll()
		if err == ERR_FILE_EOF:
			_on_background_loading_completed()
			return
		elif err == OK:
			update_progress()
		else: # Error during loading.
			print("Error while loading new scene.")
			loader = null
			return


func update_progress():
	# use load_ratio to update your Loading screen
	var load_ratio = float(loader.get_stage()) / float(loader.get_stage_count())


func _on_background_loading_completed():
	var resource = loader.get_resource()
	loader = null
	var load_time = OS.get_ticks_msec() - loading_start_time # ms
	print("{scn} loaded in {elapsed}ms".format({ 'scn': resource.resource_path, 'elapsed': load_time }))
	# artificially wait some time in order to have a gentle scene transition
	if load_time < minimum_transition_duration:
		yield(get_tree().create_timer((minimum_transition_duration - load_time) / 1000.0), "timeout")
	_set_new_scene(resource)


func _set_new_scene(resource: PackedScene):
	var current_scene = get_current_scene_node()
	current_scene.queue_free()
	var instanced_scn = resource.instance() # triggers _init
	main.active_scene_container.add_child(instanced_scn) # triggers _ready

	var transitions: Transitions = main.transitions
	transitions.fade_out()
	if instanced_scn.has_method("pre_start"):
		instanced_scn.pre_start(_params)
	yield(transitions.anim, "animation_finished")
	if instanced_scn.has_method("start"):
		instanced_scn.start()
	emit_signal("change_finished")


func _change_scene(new_scene: String, params= {}):
	emit_signal("change_started")
	var current_scene = get_current_scene_node()
	var transitions: Transitions = main.transitions
	# prevent inputs during scene change
	get_tree().paused = true
	if new_scene in scenes_denylist:
		print_debug("WARNING: ", new_scene, " is in the denylist. Loading a default scene")
		new_scene = fallback_scene
	transitions.fade_in()
	yield(transitions.anim, "animation_finished")
	var loading_start_time = OS.get_ticks_msec()
	var scn = load(new_scene)
	current_scene.queue_free()
	var instanced_scn = scn.instance() # triggers _init
	main.active_scene_container.add_child(instanced_scn) # triggers _ready
	var load_time = OS.get_ticks_msec() - loading_start_time # ms
	print("{scn} loaded in {elapsed}ms".format({ 'scn': new_scene, 'elapsed': load_time }))
	# artificially wait some time in order to have a gentle game transition
	if load_time < minimum_transition_duration:
		yield(get_tree().create_timer((minimum_transition_duration - load_time) / 1000.0), "timeout")
	transitions.fade_out()
	if instanced_scn.has_method("pre_start"):
		instanced_scn.pre_start(params)
	yield(transitions.anim, "animation_finished")
	get_tree().paused = false
	if instanced_scn.has_method("start"):
		instanced_scn.start()
	emit_signal("change_finished")


func get_current_scene_node() -> Node:
	return main.active_scene_container.get_child(0)


# --- MULTITHREAD STUFF

func _change_scene_multithread(new_scene: String, params = {}):
	emit_signal("change_started")
	_params = params
	loading_start_time = OS.get_ticks_msec()
	var transitions: Transitions = main.transitions
	transitions.fade_in()
	# TODO: start loading resources while starting the transition
	yield(transitions.anim, "animation_finished")
	scene_to_load = new_scene
	resource_multithread_loader.connect("resource_loaded", self, "_on_resource_loaded", [], CONNECT_ONESHOT)
	resource_multithread_loader.load_scene(new_scene)


func _on_resource_loaded(resource):
	var load_time = OS.get_ticks_msec() - loading_start_time # ms
	print("{scn} loaded in {elapsed}ms".format({ 'scn': resource.resource_path, 'elapsed': load_time }))
	# artificially wait some time in order to have a gentle scene transition
	if load_time < minimum_transition_duration:
		yield(get_tree().create_timer((minimum_transition_duration - load_time) / 1000.0), "timeout")
	_set_new_scene(resource)
