extends Control

@onready var host_btn := $host
@onready var join_btn := $join
@onready var ip_box := $roomcode

var peer := ENetMultiplayerPeer.new()

func _ready():
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)

	# Debug prints
	multiplayer.peer_connected.connect(func(id): print("CONNECTED:", id))
	multiplayer.peer_disconnected.connect(func(id): print("DISCONNECTED:", id))
	multiplayer.server_disconnected.connect(func(): print("SERVER CLOSED"))
	

func _on_host_pressed():
	var result := peer.create_server(7777, 2)
	if result != OK:
		print("FAILED TO HOST:", result)
		return

	multiplayer.multiplayer_peer = peer
	print("*** HOST STARTED ***")

	_load_game_scene()

func _on_join_pressed():
	var ip :String = ip_box.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"   # Default to localhost

	var result := peer.create_client(ip, 7777)
	if result != OK:
		print("FAILED TO JOIN:", result)
		return

	multiplayer.multiplayer_peer = peer
	print("*** CONNECTING TO HOST ***")

	_load_game_scene()

func _load_game_scene():
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://HandScene.tscn")
