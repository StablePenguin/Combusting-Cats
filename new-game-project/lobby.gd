extends Control

# UI nodes
@onready var code_input := $roomcode
@onready var ip_input := $ip_field   # Text or LineEdit
@onready var join_button := $join
@onready var host_button := $host
@onready var room_code_label := $code
@onready var ip_label := $ip

# TEMPORARY DEFAULT FOR LOCAL TESTING
const DEFAULT_TEST_IP := "127.0.0.1"


func _ready():
	join_button.pressed.connect(_on_join_pressed)
	host_button.pressed.connect(_on_host_pressed)

	# Show host IP (ZeroTier or fallback)
	ip_label.text = "Your IP: " + get_zerotier_ip()


func get_zerotier_ip() -> String:
	var addrs = IP.get_local_addresses()
	for a in addrs:
		if a.begins_with("192.168.196"):  # your ZeroTier range
			return a
	return DEFAULT_TEST_IP  # fallback to localhost for testing


# -----------------------------
# HOST CREATES ROOM
# -----------------------------
func _on_host_pressed():
	var room_code := str(randi_range(1000, 9999))
	room_code_label.text = "Room Code: " + room_code

	var port := int(room_code)
	var peer := ENetMultiplayerPeer.new()

	var error := peer.create_server(port, 2)
	if error != OK:
		room_code_label.text = "Error creating room."
		return

	print("SERVER STARTED on port:", port)
	multiplayer.multiplayer_peer = peer

	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://hand.tscn")


# -----------------------------
# CLIENT JOINS ROOM
# -----------------------------
func _on_join_pressed():
	var code: String = code_input.text.strip_edges()
	var host_ip: String = ip_input.text.strip_edges()

	if code.length() < 4:
		room_code_label.text = "Invalid code"
		return

	# If empty → assume 127.0.0.1 for local testing
	if host_ip == "":
		host_ip = DEFAULT_TEST_IP
		print("No IP entered, using default:", host_ip)

	var port := int(code)

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_ip, port)

	if error != OK:
		room_code_label.text = "Failed to connect."
		return

	multiplayer.multiplayer_peer = peer

	print("CLIENT CONNECTING to", host_ip, ":", port)

	multiplayer.connected_to_server.connect(_on_join_success)
	multiplayer.connection_failed.connect(_on_join_fail)


func _on_join_success():
	print("CLIENT: Connected!")
	get_tree().change_scene_to_file("res://hand.tscn")


func _on_join_fail():
	room_code_label.text = "Connection failed."
