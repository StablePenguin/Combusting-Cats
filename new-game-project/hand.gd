extends Control

@onready var opponent_area: Control = $opponentcards
var card_back: Texture2D = preload("res://cards/card_back.png")

# ======================================================
#  CARD TYPE ↔ TEXTURE MAPS
# ======================================================

var type_to_texture := {
	"cat_tac": preload("res://cards/cat tac card.png"),
	"cat_alope": preload("res://cards/cat-alope card.png"),
	"cat_yam": preload("res://cards/yam cat with hair card.png"),
	"cat_goatee": preload("res://cards/goatee cat card.png"),
	"cat_gay": preload("res://cards/gay cat card.png"),

	"combusting_cat": preload("res://cards/combusting cat card.png"),
	"deactivate": preload("res://cards/deactivate card.png"),
	"rearrange": preload("res://cards/rearrange card.png"),
	"commence_hostilities": preload("res://cards/commence hostilities card.png"),
	"omit": preload("res://cards/omit card.png"),
	"no": preload("res://cards/no card.png"),
	"indulgence": preload("res://cards/indulgence card.png"),
	"view_2050": preload("res://cards/view 2050 card.png")
}

func texture_to_type(tex: Texture2D) -> String:
	for t in type_to_texture.keys():
		if type_to_texture[t] == tex:
			return t
	return ""

# ======================================================
#  GAME STATE
# ======================================================

var discard_pile: Array[String] = []
@onready var discard_area: TextureRect = $discard

var is_my_turn := false
var cards_played_this_turn: Array[String] = []

var player_id: int
var player_hands: Dictionary = {}
var current_turn: int = 0

var card_scene := preload("res://card.tscn")
var cards: Array[TextureRect] = []
var deck: Array[String] = []

var deck_contents := {
	"cat_tac": 4,
	"cat_yam": 4,
	"cat_alope": 4,
	"cat_gay": 4,
	"cat_goatee": 4,
	"indulgence": 4,
	"no": 5,
	"omit": 4,
	"rearrange": 4,
	"view_2050": 5,
	"commence_hostilities": 4,
	"deactivate": 2,
	"combusting_cat": 1
}

# ======================================================
#  READY
# ======================================================

func _ready():
	player_id = multiplayer.get_unique_id()
	print("My ID:", player_id)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id): print("DISCONNECTED:", id))
	multiplayer.server_disconnected.connect(func(): print("SERVER LOST"))

	if multiplayer.is_server():
		player_hands.clear()
		player_hands[player_id] = []
		build_safe_deck()

		for p in multiplayer.get_peers():
			if not player_hands.has(p):
				player_hands[p] = []

		_try_start_game()
	else:
		rpc_id(1, "request_sync")

func _process(_delta):
	$Button.visible = is_my_turn

# ======================================================
#  CONNECTION + GAME START
# ======================================================

func _on_peer_connected(id):
	if multiplayer.is_server():
		player_hands[id] = []
		_try_start_game()

func _try_start_game():
	if not multiplayer.is_server(): return

	if player_hands.size() < 2:
		print("Waiting for second player…")
		return

	print("Starting game…")

	if deck.is_empty():
		build_safe_deck()

	deal_starting_hands()
	insert_bombs()
	deck.shuffle()

	for id in player_hands.keys():
		rpc_id(id, "sync_state", deck, discard_pile, player_hands[id], player_hands)

	server_set_turn(1)

# ======================================================
#  TURN HANDLING
# ======================================================

func server_set_turn(id: int):
	if not multiplayer.is_server(): return

	current_turn = id
	cards_played_this_turn.clear()

	rpc("client_set_turn", current_turn)

@rpc("any_peer", "call_local")
func client_set_turn(turn_id: int):
	is_my_turn = (turn_id == player_id)
	print("My turn:", is_my_turn)

# ======================================================
#  SYNC SYSTEM
# ======================================================

@rpc("any_peer", "call_local")
func sync_state(server_deck, server_discard, my_hand, all_hands):
	deck = server_deck
	discard_pile = server_discard
	player_hands = all_hands

	rebuild_hand(my_hand)
	rebuild_opponent_hand()

	if discard_pile.size() > 0:
		var last = discard_pile[-1]
		if type_to_texture.has(last):
			discard_area.texture = type_to_texture[last]

@rpc("any_peer")
func request_sync():
	if multiplayer.is_server():
		var id = multiplayer.get_remote_sender_id()
		rpc_id(id, "sync_state", deck, discard_pile, player_hands[id], player_hands)

# ======================================================
#  HAND DISPLAY
# ======================================================

func rebuild_hand(hand_types: Array):
	for c in cards: c.queue_free()
	cards.clear()

	for type in hand_types:
		if type_to_texture.has(type):
			add_card(type_to_texture[type])

	update_card_positions()

func rebuild_opponent_hand():
	for c in opponent_area.get_children():
		c.queue_free()

	var opp_id = -1
	for id in player_hands.keys():
		if id != player_id:
			opp_id = id
			break
	if opp_id == -1:
		return

	var count = player_hands[opp_id].size()

	# Fixed card dimensions
	var card_size = Vector2(134.0, 185.849)
	var area_width = opponent_area.size.x

	# Proper spacing: overlap slightly if needed
	var spacing = min(card_size.x, area_width / max(count, 1))

	var x := 0.0

	for i in count:
		var tr := TextureRect.new()
		tr.texture = card_back
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = card_size

		tr.position = Vector2(x, 0)
		opponent_area.add_child(tr)

		x += spacing




func _update_opponent_positions(card_list: Array):
	if card_list.is_empty():
		return

	var card_width :float= card_list[0].size.x
	var max_width :float= opponent_area.size.x

	var spacing := card_width
	if card_list.size() * spacing > max_width:
		spacing = max_width / card_list.size()

	var x := 0.0
	for c in card_list:
		c.position = Vector2(x, 0)
		x += spacing


# ======================================================
#  DECK + DEAL
# ======================================================

func build_safe_deck():
	deck.clear()
	for type in deck_contents.keys():
		if type == "combusting_cat" or type == "deactivate": continue
		for i in deck_contents[type]:
			deck.append(type)
	deck.shuffle()

func deal_starting_hands():
	for p in player_hands.keys():
		var hand: Array[String] = []
		for i in 7:
			hand.append(deck.pop_back())
		hand.append("deactivate")
		player_hands[p] = hand

func insert_bombs():
	for i in deck_contents["deactivate"]:
		deck.append("deactivate")
	deck.append("combusting_cat")

# ======================================================
#  DRAW CARD (FULLY FIXED)
# ======================================================

@rpc("any_peer")
func server_draw_card(p_id: int):
	if not multiplayer.is_server(): return
	if p_id != current_turn: return

	var type = deck.pop_back()
	player_hands[p_id].append(type)

	# Sync ALL players
	for id in player_hands.keys():
		rpc_id(id, "sync_state", deck, discard_pile, player_hands[id], player_hands)

	var ids = player_hands.keys()
	var next_turn = ids[0] if ids[0] != p_id else ids[1]
	server_set_turn(next_turn)

# ======================================================
#  PLAY CARD
# ======================================================

func _on_card_played(card: TextureRect):
	if not is_my_turn:
		return

	var t := texture_to_type(card.texture)
	if t == "":
		return

	# Duplicate the card for animation only
	var anim_card := card.duplicate()
	get_tree().current_scene.add_child(anim_card)

	# Position clone exactly on top of original card
	anim_card.global_position = card.global_position
	anim_card.scale = card.scale

	# Remove original card immediately (prevent lambda issues)
	cards.erase(card)
	card.queue_free()

	# Convert discard to local space of the root
	var world_target := discard_area.get_global_transform_with_canvas().origin
	var parent_xform: Transform2D = anim_card.get_parent().get_global_transform_with_canvas()
	var local_target: Vector2 = parent_xform.affine_inverse().basis_xform(world_target)

	# Animate clone
	animate_card_to_discard(anim_card, local_target, func():
		anim_card.queue_free()
	)

	# Tell server the card was played
	if multiplayer.is_server():
		server_play_card(player_id, t)
	else:
		rpc_id(1, "server_play_card", player_id, t)

func animate_card_to_discard(card: TextureRect, target_local_pos: Vector2, callback: Callable = Callable()):
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(card, "scale", Vector2(1.2, 1.2), 0.12)
	tween.tween_property(card, "position", target_local_pos, 0.25)
	tween.tween_property(card, "modulate:a", 0.0, 0.15)

	if callback.is_valid():
		tween.finished.connect(callback)


@rpc("any_peer")
func server_play_card(p_id: int, type: String):
	if not multiplayer.is_server(): return
	if p_id != current_turn: return
	if not player_hands[p_id].has(type): return
	rpc("client_animate_opponent_play", p_id)

	player_hands[p_id].erase(type)
	discard_pile.append(type)

	discard_area.texture = type_to_texture[type]
	cards_played_this_turn.append(type)

	var ends_turn := apply_card_effect(p_id, type)

	for id in player_hands.keys():
		rpc_id(id, "sync_state", deck, discard_pile, player_hands[id], player_hands)

	if ends_turn:
		var ids = player_hands.keys()
		var next_turn = ids[0] if ids[0] != p_id else ids[1]
		server_set_turn(next_turn)
	else:
		print("Player must draw to end turn.")

@rpc("call_local")
func client_animate_opponent_play(p_id: int) -> void:
	if p_id == player_id:
		return

	var opp_cards: Array = opponent_area.get_children()
	if opp_cards.size() == 0:
		return

	var opp_card: TextureRect = opp_cards[-1] as TextureRect
	if opp_card == null:
		return

	# Create clone used only for animation
	var anim_card := TextureRect.new()
	anim_card.texture = card_back
	anim_card.stretch_mode = TextureRect.STRETCH_SCALE
	anim_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	anim_card.size = Vector2(134, 186)

	# Starting global position = opponent card's global position
	var start_global: Vector2 = opp_card.get_global_transform().origin
	anim_card.global_position = start_global

	# Add animation card to scene root so it isn't removed on sync
	get_tree().current_scene.add_child(anim_card)

	# Target global position = discard pile position
	var target_global: Vector2 = discard_area.get_global_transform().origin

	# Convert global → local space of anim_card's parent
	var parent_xform: Transform2D = anim_card.get_parent().get_global_transform()
	var local_target: Vector2 = parent_xform.affine_inverse() * target_global

	# Animate card flying to discard pile
	animate_card_to_discard(anim_card, local_target, func() -> void:
		anim_card.queue_free()
	)




# ======================================================
#  CARD EFFECTS
# ======================================================

func apply_card_effect(p_id: int, type: String) -> bool:
	if type.begins_with("cat_"):
		handle_cat_play_server(p_id, type)
		return false

	match type:
		"omit": return true
		"commence_hostilities": return true
		"rearrange":
			deck.shuffle()
			return false
		"view_2050":
			_show_top_cards(p_id)
			return false
		_:
			return false

func handle_cat_play_server(p_id: int, cat_type: String):
	var count = cards_played_this_turn.count(cat_type)
	if count == 2: print("2-of-a-kind by", p_id)
	if count == 3: print("3-of-a-kind by", p_id)

func _show_top_cards(p_id: int):
	var preview: Array[String] = []
	for i in min(3, deck.size()):
		preview.append(deck[deck.size() - 1 - i])
	rpc_id(p_id, "client_show_future", preview)

@rpc("any_peer", "call_local")
func client_show_future(arr):
	print("TOP CARDS:")
	for s in arr: print("  ", s)

# ======================================================
#  CARD VISUALS
# ======================================================

func add_card(texture: Texture2D):
	var c = card_scene.instantiate()
	c.texture = texture
	c.connect("card_played", Callable(self, "_on_card_played"))
	add_child(c)
	cards.append(c)

func update_card_positions():
	if cards.is_empty(): return
	var spacing = min(cards[0].size.x, size.x / cards.size())
	var x := 0.0
	for c in cards:
		c.position = Vector2(x, 0)
		x += spacing

# ======================================================
#  DRAW BUTTON
# ======================================================

func _on_button_pressed():
	if not is_my_turn: return
	if multiplayer.is_server():
		server_draw_card(player_id)
	else:
		rpc_id(1, "server_draw_card", player_id)
