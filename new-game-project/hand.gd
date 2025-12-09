extends Control

# ---------- STATE ----------
var discard_pile: Array[Texture2D] = []
@onready var discard_area: TextureRect = $discard

var is_my_turn: bool = false
var cards_played_this_turn: Array[String] = []

var player_id: int
var player_hands: Dictionary = {}                  # peer_id -> Array[Texture2D]
var current_turn: int = 0                          # will be set when game starts

var card_scene: PackedScene = preload("res://Card.tscn")
var cards: Array[TextureRect] = []                 # visual cards in *this* player's hand
var deck: Array[Texture2D] = []                    # server-owned deck

# ---------- CARD TEXTURES ----------
var cat_tac: Texture2D = preload("res://cards/cat tac card.png")
var cat_alope: Texture2D = preload("res://cards/cat-alope card.png")
var combusting_cat: Texture2D = preload("res://cards/combusting cat card.png")   # Exploding Kitten
var commence_hostilities: Texture2D = preload("res://cards/commence hostilities card.png")
var deactivate: Texture2D = preload("res://cards/deactivate card.png")           # Defuse
var gay_cat: Texture2D = preload("res://cards/gay cat card.png")
var goatee_cat: Texture2D = preload("res://cards/goatee cat card.png")
var indulgence: Texture2D = preload("res://cards/indulgence card.png")
var no: Texture2D = preload("res://cards/no card.png")
var omit: Texture2D = preload("res://cards/omit card.png")
var rearrange: Texture2D = preload("res://cards/rearrange card.png")
var view_2050: Texture2D = preload("res://cards/view 2050 card.png")
var yam_cat: Texture2D = preload("res://cards/yam cat with hair card.png")

var card_types := {
	cat_tac: "cat_tac",
	cat_alope: "cat_alope",
	yam_cat: "cat_yam",
	goatee_cat: "cat_goatee",
	gay_cat: "cat_gay",

	combusting_cat: "combusting_cat",
	deactivate: "deactivate",
	rearrange: "rearrange",
	commence_hostilities: "commence_hostilities",
	omit: "omit",
	no: "no",
	indulgence: "indulgence",
	view_2050: "view_2050"
}

# ---------- DECK CONTENTS ----------
var deck_contents := {
	cat_tac: 4,
	yam_cat: 4,
	cat_alope: 4,
	gay_cat: 4,
	goatee_cat: 4,
	indulgence: 4,
	no: 5,
	omit: 4,
	rearrange: 4,
	view_2050: 5,
	commence_hostilities: 4,
	deactivate: 2,        # extra defuses in deck
	combusting_cat: 1
}


func debug_rpc(msg: String) -> void:
	print("🔵 RPC:", msg)


func _ready() -> void:
	# Debug connections
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int):
		print("DISCONNECTED:", id))
	multiplayer.server_disconnected.connect(func():
		print("LOST CONNECTION TO SERVER"))

	player_id = multiplayer.get_unique_id()
	print("My ID:", player_id)

	if multiplayer.is_server():
		print("SERVER: setting up game")

		# Ensure dictionary is clean and register host as a player
		player_hands.clear()
		player_hands[player_id] = []   # host

		# Build safe deck (no bombs / defuses yet)
		build_starting_deck_safe()

		# If client already connected (scene change after lobby), register them too
		var peers = Array(multiplayer.get_peers())
		for id in peers:
			if not player_hands.has(id):
				player_hands[id] = []
		_try_start_game()
	else:
		print("CLIENT: requesting sync from server…")
		rpc_id(1, "request_sync")


func _process(_delta: float) -> void:
	$Button.visible = is_my_turn


# ===========================
#  CONNECTION & START
# ===========================

func _on_peer_connected(id: int) -> void:
	print("CONNECTED:", id)

	if not multiplayer.is_server():
		return

	if not player_hands.has(id):
		player_hands[id] = []

	_try_start_game()


func _try_start_game() -> void:
	# Only server calls this
	if not multiplayer.is_server():
		return

	# We want exactly 2 players: host + 1 client
	if player_hands.size() < 2:
		print("SERVER: waiting for second player...")
		return

	print("SERVER: both players present, dealing hands")

	# (Re)build safe deck if empty
	if deck.is_empty():
		build_starting_deck_safe()

	# Deal 7 safe cards + 1 starting defuse each
	deal_starting_hands()
	insert_bombs_and_defuses()
	deck.shuffle()

	# Sync both players
	for p_id in player_hands.keys():
		var hand: Array = player_hands[p_id]
		rpc_id(p_id, "sync_state", deck, discard_pile, hand)

	# Start with host's turn
	var host_id: int = 1  # ENet host is always 1
	server_start_turn(host_id)


func server_start_turn(new_turn_id: int) -> void:
	# SERVER: change turn and tell everyone
	if not multiplayer.is_server():
		return

	current_turn = new_turn_id
	cards_played_this_turn.clear()

	for id in player_hands.keys():
		rpc_id(id, "client_set_turn", current_turn)


# ===========================
#  SYNC / HAND VISUAL
# ===========================

@rpc("authority", "call_local")
func sync_state(server_deck: Array, server_discard: Array, my_hand: Array) -> void:
	deck = server_deck
	discard_pile = server_discard
	rebuild_hand_visual(my_hand)


@rpc("any_peer")
func request_sync() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not player_hands.has(sender_id):
		return

	var my_hand: Array = player_hands[sender_id]
	rpc_id(sender_id, "sync_state", deck, discard_pile, my_hand)


func rebuild_hand_visual(hand: Array) -> void:
	# Clear old graphic cards
	for c in cards:
		c.queue_free()
	cards.clear()

	# Build visuals from textures
	for tex in hand:
		var t: Texture2D = tex
		add_card(t)

	update_card_positions()


# ===========================
#  TURN SYNC TO CLIENT
# ===========================

@rpc("authority", "call_local")
func client_set_turn(turn_id: int) -> void:
	is_my_turn = (turn_id == player_id)
	print("client_set_turn -> My turn:", is_my_turn)


# ===========================
#  DECK BUILDING & DEAL
# ===========================

# Build deck WITHOUT bombs/defuses, for safe starting hands
func build_starting_deck_safe() -> void:
	var deck_no_bombs: Array[Texture2D] = []

	for texture in deck_contents.keys():
		if texture == deactivate or texture == combusting_cat:
			continue
		var count: int = deck_contents[texture]
		for i in count:
			deck_no_bombs.append(texture)

	deck_no_bombs.shuffle()
	deck = deck_no_bombs


# Deal 7 safe cards + 1 starting defuse to each player
func deal_starting_hands() -> void:
	var ids: Array = player_hands.keys()
	for p_id in ids:
		var hand: Array[Texture2D] = []
		# 7 safe cards
		for i in 7:
			if deck.is_empty():
				break
			var card_tex: Texture2D = deck.pop_back()
			hand.append(card_tex)
		# 1 defuse in starting hand
		hand.append(deactivate)
		player_hands[p_id] = hand


# After hands dealt, bombs + extra defuses go into deck
func insert_bombs_and_defuses() -> void:
	var extra_defuse_count: int = deck_contents[deactivate]
	for i in extra_defuse_count:
		deck.append(deactivate)

	deck.append(combusting_cat)


func discard_card(texture: Texture2D) -> void:
	discard_pile.append(texture)
	discard_area.texture = texture


# ===========================
#  SERVER — DRAW CARD
# ===========================

@rpc("any_peer")
func server_draw_card(p_id: int) -> void:
	debug_rpc("server_draw_card from " + str(p_id))

	if not multiplayer.is_server():
		return

	if p_id != current_turn:
		print("server_draw_card: not your turn")
		return

	if deck.is_empty():
		print("Deck is empty on server!")
		return

	var tex: Texture2D = deck.pop_back()
	var hand: Array = player_hands[p_id]
	hand.append(tex)
	player_hands[p_id] = hand

	# Sync that player's hand + shared deck/discard
	rpc_id(p_id, "sync_state", deck, discard_pile, player_hands[p_id])

	# End turn, pass to opponent
	var ids: Array = player_hands.keys()
	var next_turn: int = ids[0]
	if next_turn == p_id:
		next_turn = ids[1]
	server_start_turn(next_turn)


# ===========================
#  CARD NODE CREATION
# ===========================

func add_card(texture: Texture2D) -> void:
	var card: TextureRect = card_scene.instantiate()
	card.texture = texture
	card.connect("card_played", Callable(self, "_on_card_played"))
	add_child(card)
	cards.append(card)


# ===========================
#  CLIENT-SIDE VALIDATION
# ===========================

func can_play_card(type: String) -> bool:
	# Disallow Exploding Kitten as a normal play (MP bomb logic not wired yet)
	if type == "combusting_cat":
		print("You cannot play the Exploding Kitten directly (yet).")
		return false

	# Cat cards need combos
	if type.begins_with("cat_"):
		var cats_in_hand: int = count_cat_in_hand(type)
		var played_this_turn: int = 0
		for c in cards_played_this_turn:
			if c == type:
				played_this_turn += 1

		if played_this_turn >= 3:
			print("You already used this cat combo this turn.")
			return false

		if played_this_turn == 0:
			if cats_in_hand >= 2:
				return true
			print("You need TWO matching cats in your hand to start a combo.")
			return false

		return true

	# For now, allow all other action cards
	return true


func count_cat_in_hand(type: String) -> int:
	var count: int = 0
	for card in cards:
		var tex: Texture2D = card.texture
		var t: String = card_types[tex]
		if t == type:
			count += 1
	return count


# ===========================
#  SERVER — HANDLE CARD PLAY
# ===========================

@rpc("any_peer")
func server_play_card(p_id: int, type: String) -> void:
	debug_rpc("server_play_card from " + str(p_id) + " with card " + type)

	if not multiplayer.is_server():
		return

	if p_id != current_turn:
		print("server_play_card: not your turn")
		return

	if not player_hands.has(p_id):
		print("server_play_card: unknown player id", p_id)
		return

	var hand: Array = player_hands[p_id]

	# Find matching card texture in player's hand
	var found_index: int = -1
	for i in hand.size():
		var tex_i: Texture2D = hand[i]
		if card_types[tex_i] == type:
			found_index = i
			break

	if found_index == -1:
		print("Player tried to play a card they don't have:", type)
		return

	var played_tex: Texture2D = hand.pop_at(found_index)
	player_hands[p_id] = hand
	discard_pile.append(played_tex)

	# Track for combos (server-side)
	cards_played_this_turn.append(type)

	# Apply effect
	apply_card_effect(p_id, type)

	# Sync both players' deck/discard + their hands
	for id in player_hands.keys():
		var h: Array = player_hands[id]
		rpc_id(id, "sync_state", deck, discard_pile, h)

	# Default: end turn and pass to other player
	var ids: Array = player_hands.keys()
	var next_turn: int = ids[0]
	if next_turn == p_id:
		next_turn = ids[1]
	server_start_turn(next_turn)


func apply_card_effect(p_id: int, type: String) -> void:
	# Cat combos handled separately
	if type.begins_with("cat_"):
		handle_cat_play_server(p_id, type)
		return

	match type:
		"commence_hostilities":
			apply_attack(p_id)
		"omit":
			apply_skip(p_id)
		"no":
			apply_nope(p_id)
		"indulgence":
			apply_favor(p_id)
		"view_2050":
			apply_see_future(p_id)
		"rearrange":
			apply_shuffle(p_id)
		"deactivate":
			print("Server: Defuse effect not wired in MP yet.")
		"combusting_cat":
			print("Server: Bomb effect not wired in MP yet.")


# ---------- SERVER ACTION CARD IMPLEMENTATIONS ----------

func apply_attack(p_id: int) -> void:
	print("SERVER: ATTACK from player", p_id)
	# Real Exploding Kittens logic (two turns) can be implemented later.


func apply_skip(p_id: int) -> void:
	print("SERVER: SKIP by player", p_id)
	# Turn switching is handled after apply_card_effect() by server_play_card.


func apply_nope(p_id: int) -> void:
	print("SERVER: NOPE played (stack/undo logic not implemented).")


func apply_favor(p_id: int) -> void:
	print("SERVER: FAVOR played (opponent gives a card — not implemented yet).")


func apply_see_future(p_id: int) -> void:
	var count: int = min(3, deck.size())
	var reveal: Array[Texture2D] = []

	for i in count:
		var idx: int = deck.size() - 1 - i
		var tex: Texture2D = deck[idx]
		reveal.append(tex)

	print("SERVER: Sending See The Future cards to player", p_id)
	rpc_id(p_id, "client_show_future", reveal)


@rpc("authority", "call_local")
func client_show_future(cards_arr: Array) -> void:
	print("--- TOP CARDS ---")
	for tex in cards_arr:
		var t: String = card_types[tex]
		print("  ", t)


func apply_shuffle(p_id: int) -> void:
	deck.shuffle()
	print("SERVER: Deck shuffled.")


# ---------- SERVER CAT COMBOS ----------

func handle_cat_play_server(p_id: int, cat_type: String) -> void:
	var count: int = 0
	for c in cards_played_this_turn:
		if c == cat_type:
			count += 1

	if count == 2:
		print("SERVER: TWO-OF-A-KIND for", cat_type, "by player", p_id)
		# TODO: steal random card from opponent

	if count == 3:
		print("SERVER: THREE-OF-A-KIND for", cat_type, "by player", p_id)
		# TODO: steal specific card from opponent


# ===========================
#  CLIENT — CARD CLICK
# ===========================

func _on_card_played(card: TextureRect) -> void:
	if not is_my_turn:
		print("It's not your turn!")
		return

	var tex: Texture2D = card.texture
	var type: String = card_types[tex]

	if not can_play_card(type):
		return

	# Just ask the server to play this card.
	# Visuals will update via sync_state().
	rpc_id(1, "server_play_card", player_id, type)


# ===========================
#  LAYOUT & DRAW BUTTON
# ===========================

func update_card_positions() -> void:
	if cards.is_empty():
		return

	var card_width: float = cards[0].size.x
	var max_width: float = size.x

	var spacing: float = card_width
	if cards.size() * spacing > max_width:
		spacing = max_width / cards.size()

	var x: float = 0.0
	for card in cards:
		card.position = Vector2(x, 0)
		x += spacing


func _on_button_pressed() -> void:
	# ask server to draw a card for this player
	rpc_id(1, "server_draw_card", player_id)
