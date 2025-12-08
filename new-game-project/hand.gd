extends Control

# ---------- STATE ----------
var discard_pile = []                       # list of discarded textures
@onready var discard_area = $discard        # TextureRect showing top of pile

var is_my_turn = false
var cards_played_this_turn = []             # for cat combos

var player_id
var player_hands = {}                       # { peer_id: [Texture2D, ...] }
var current_turn = 1                        # 1 = host, 2 = client

var card_scene = preload("res://Card.tscn")
var cards = []                              # visual card nodes in this player's hand
var deck = []                               # array of Texture2D

# ---------- CARD TEXTURES ----------
var cat_tac = preload("res://cards/cat tac card.png")
var cat_alope = preload("res://cards/cat-alope card.png")
var combusting_cat = preload("res://cards/combusting cat card.png")   # Exploding Kitten
var commence_hostilities = preload("res://cards/commence hostilities card.png")
var deactivate = preload("res://cards/deactivate card.png")           # Defuse
var gay_cat = preload("res://cards/gay cat card.png")
var goatee_cat = preload("res://cards/goatee cat card.png")
var indulgence = preload("res://cards/indulgence card.png")
var no = preload("res://cards/no card.png")
var omit = preload("res://cards/omit card.png")
var rearrange = preload("res://cards/rearrange card.png")
var view_2050 = preload("res://cards/view 2050 card.png")
var yam_cat = preload("res://cards/yam cat with hair card.png")

var card_types = {
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
var deck_contents = {
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
	deactivate: 2,
	combusting_cat: 1
}

func debug_rpc(msg:String):
	print("🔵 RPC:", msg)

func _ready():
	# --- Debug prints ---
	multiplayer.peer_connected.connect(func(id):
		print("CONNECTED:", id))
	
	multiplayer.peer_disconnected.connect(func(id):
		print("DISCONNECTED:", id))

	multiplayer.server_disconnected.connect(func():
		print("LOST CONNECTION TO SERVER"))

	# Identify player
	player_id = multiplayer.get_unique_id()
	print("My ID:", player_id)

	# --- HOST / SERVER SIDE ---
	if multiplayer.is_server():
		print("SERVER: Initializing game state")

		# Initialize hands dictionary
		player_hands[1] = []
		player_hands[2] = []

		# Build deck & safe starting hands
		build_starting_deck_safe()
		deal_starting_hands()

		# Add bombs + defuses AFTER starting hands
		insert_bombs_and_defuses()
		deck.shuffle()

		# Tell both clients whose turn it is
		for id in [1, 2]:
			rpc_id(id, "client_set_turn", current_turn)

		# Server must manually sync itself (no RPC needed)
		var my_hand = player_hands[player_id]
		sync_state(deck, discard_pile, my_hand)

	# --- CLIENT SIDE ---
	else:
		print("CLIENT: requesting sync from server…")
		rpc_id(1, "request_sync")


func _process(_delta):
	$Button.visible = is_my_turn


# ===========================
#  SYNC / HAND VISUAL
# ===========================

@rpc("authority", "call_local")
func sync_state(server_deck, server_discard, my_hand):
	deck = server_deck
	discard_pile = server_discard
	rebuild_hand_visual(my_hand)

@rpc("any_peer")
func request_sync():
	if multiplayer.is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		if not player_hands.has(sender_id):
			return
		var my_hand = player_hands[sender_id]
		rpc_id(sender_id, "sync_state", deck, discard_pile, my_hand)

func rebuild_hand_visual(hand):
	# delete old nodes
	for c in cards:
		c.queue_free()
	cards.clear()

	# create new visual cards from textures
	for tex in hand:
		add_card(tex)

	update_card_positions()


# ===========================
#  TURN SYNC
# ===========================

@rpc("authority", "call_local")
func client_set_turn(turn_id):
	is_my_turn = (turn_id == player_id)
	print("My turn:", is_my_turn)


# ===========================
#  DECK BUILDING & DEAL
# ===========================

# Build deck WITHOUT bombs/defuses, for safe starting hands
func build_starting_deck_safe():
	var deck_no_bombs = []

	for texture in deck_contents.keys():
		if texture == deactivate or texture == combusting_cat:
			continue
		var count = deck_contents[texture]
		for i in count:
			deck_no_bombs.append(texture)

	deck_no_bombs.shuffle()
	deck = deck_no_bombs

# Deal 7 safe cards to each player
func deal_starting_hands():
	for p in [1, 2]:
		for i in 7:
			if deck.is_empty():
				break
			var card_tex = deck.pop_back()
			player_hands[p].append(card_tex)

# After hands dealt, bombs + extra defuses go into deck
func insert_bombs_and_defuses():
	for i in deck_contents[deactivate]:
		deck.append(deactivate)
	deck.append(combusting_cat)

func discard_card(texture):
	discard_pile.append(texture)
	discard_area.texture = texture


# ===========================
#  DRAW CARD (SERVER)
# ===========================

@rpc("any_peer")
func server_draw_card(p_id):
	debug_rpc("server_draw_card from " + str(p_id))
	if not multiplayer.is_server():
		return

	if p_id != current_turn:
		print("server_draw_card: wrong turn")
		return

	if deck.is_empty():
		print("Deck is empty on server!")
		return

	var tex = deck.pop_back()
	player_hands[p_id].append(tex)

	# sync that player's hand + shared deck/discard
	rpc_id(p_id, "sync_state", deck, discard_pile, player_hands[p_id])

	# advance turn
	current_turn = 2 if p_id == 1 else 1
	for id in [1, 2]:
		rpc_id(id, "client_set_turn", current_turn)


# ===========================
#  CARD NODE CREATION
# ===========================

func add_card(texture):
	var card = card_scene.instantiate()
	card.texture = texture
	card.connect("card_played", Callable(self, "_on_card_played"))
	add_child(card)
	cards.append(card)
	update_card_positions()


# ===========================
#  CLIENT-SIDE VALIDATION
# ===========================

func can_play_card(type):
	# Disallow Exploding Kitten as a manual play (for now)
	if type == "combusting_cat":
		print("You cannot play the Exploding Kitten directly.")
		return false

	# Example: basic cats need combos
	if type.begins_with("cat_"):
		var cats_in_hand = count_cat_in_hand(type)
		var played_this_turn = 0
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

func count_cat_in_hand(type):
	var count = 0
	for card in cards:
		var tex = card.texture
		var t = card_types[tex]
		if t == type:
			count += 1
	return count


# ===========================
#  SERVER — HANDLE CARD PLAY
# ===========================

@rpc("any_peer")
func server_play_card(p_id, type):
	debug_rpc("server_play_card from " + str(p_id) + " with card " + type)
	if not multiplayer.is_server():
		return

	if p_id != current_turn:
		print("server_play_card: not your turn")
		return

	if not player_hands.has(p_id):
		print("server_play_card: unknown player id", p_id)
		return

	# Make sure this player actually has that card type
	var found_index = -1
	for i in player_hands[p_id].size():
		var tex = player_hands[p_id][i]
		if card_types[tex] == type:
			found_index = i
			break

	if found_index == -1:
		print("Player tried to play a card they don't have:", type)
		return

	var played_tex = player_hands[p_id].pop_at(found_index)
	discard_pile.append(played_tex)

	# track for combos (server-side)
	cards_played_this_turn.append(type)

	# apply effect on server
	apply_card_effect(p_id, type)

	# sync both players' views of deck/discard + THEIR hand
	for id in [1, 2]:
		var hand = player_hands[id]
		rpc_id(id, "sync_state", deck, discard_pile, hand)

	# advance turn (basic version, will improve later with Attack/Skip)
	current_turn = 2 if current_turn == 1 else 1
	for id in [1, 2]:
		rpc_id(id, "client_set_turn", current_turn)


func apply_card_effect(p_id, type):
	# cat combos handled separately
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
			print("Server: Defuse effect not wired yet in MP.")
		"combusting_cat":
			print("Server: Bomb effect not wired yet in MP.")


# ---------- SERVER ACTION CARD IMPLEMENTATIONS ----------

func apply_attack(p_id):
	print("SERVER: ATTACK from player", p_id)
	# For now, just pass the turn to opponent normally.
	current_turn = 2 if p_id == 1 else 1
	for id in [1, 2]:
		rpc_id(id, "client_set_turn", current_turn)

func apply_skip(p_id):
	print("SERVER: SKIP by player", p_id)
	current_turn = 2 if p_id == 1 else 1
	for id in [1, 2]:
		rpc_id(id, "client_set_turn", current_turn)

func apply_nope(p_id):
	print("SERVER: NOPE played (no stack/undo logic yet).")

func apply_favor(p_id):
	print("SERVER: FAVOR played (opponent gives a card — not implemented yet).")

func apply_see_future(p_id):
	var count = min(3, deck.size())
	var reveal = []

	for i in count:
		reveal.append(deck[deck.size() - 1 - i])

	print("SERVER: Sending See The Future cards to player", p_id)
	rpc_id(p_id, "client_show_future", reveal)

@rpc("call_local")
func client_show_future(cards_arr):
	print("--- TOP CARDS ---")
	for tex in cards_arr:
		print("  ", card_types[tex])

func apply_shuffle(p_id):
	deck.shuffle()
	print("SERVER: Deck shuffled.")


# ---------- SERVER CAT COMBOS ----------

func handle_cat_play_server(p_id, cat_type):
	var key = str(p_id) + "_" + cat_type

	# count how many of this cat type played this turn
	var count = 0
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

func _on_card_played(card):
	if not is_my_turn:
		print("It's not your turn!")
		return

	var tex = card.texture
	var type = card_types[tex]

	if not can_play_card(type):
		return

	# ask the server to play this card type
	rpc_id(1, "server_play_card", player_id, type)


# ===========================
#  LAYOUT & DRAW BUTTON
# ===========================

func update_card_positions():
	if cards.is_empty():
		return

	var card_width = cards[0].size.x
	var max_width = size.x

	var spacing = card_width
	if cards.size() * spacing > max_width:
		spacing = max_width / cards.size()

	var x = 0.0
	for card in cards:
		card.position = Vector2(x, 0)
		x += spacing


func _on_button_pressed():
	# ask server to draw a card for this player
	rpc_id(1, "server_draw_card", player_id)
