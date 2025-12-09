extends Control

const DEFAULT_IP := "192.168.196.76"  # LAN only. Replace with real IP for online play.

@onready var code_input := $roomcode
@onready var join_button := $join
@onready var host_button := $host
@onready var room_code_label := $code

func _ready():
	join_button.pressed.connect(_on_join_pressed)
	host_button.pressed.connect(_on_host_pressed)


# -----------------------------
# HOST CREATES ROOM
# -----------------------------
func _on_host_pressed():
	var room_code = str(randi_range(1000, 9999))  # 4-digit code
	room_code_label.text = "Room Code: " + room_code

	# Use room code as PORT
	var port = int(room_code)

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 2)

	if error != OK:
		room_code_label.text = "Error creating room."
		return

	multiplayer.multiplayer_peer = peer
	print("SERVER STARTED on port:", port)

	# Load game scene for host
	await get_tree().create_timer(5).timeout
	get_tree().change_scene_to_file("res://Hand.tscn")


# -----------------------------
# CLIENT JOINS ROOM
# -----------------------------
func _on_join_pressed():
	var code = code_input.text.strip_edges()
	if code.length() < 4:
		room_code_label.text = "Invalid code"
		return

	var port = int(code)

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(DEFAULT_IP, port)

	if error != OK:
		room_code_label.text = "Failed to connect."
		return

	multiplayer.multiplayer_peer = peer

	print("CLIENT CONNECTING to port:", port)

	# Client loads game scene after connection is successful
	multiplayer.connected_to_server.connect(_on_join_success)
	multiplayer.connection_failed.connect(_on_join_fail)


func _on_join_success():
	print("CLIENT: Connected!")
	get_tree().change_scene_to_file("res://hand.tscn")


func _on_join_fail():
	room_code_label.text = "Connection failed."
