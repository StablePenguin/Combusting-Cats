extends Control

var bomb_drawn := false
var pending_bomb_texture: Texture2D = null
var discard_pile := []			# list of all discarded textures
@onready var discard_area := $discard	# TextureRect showing top of pile
var is_my_turn = true      # later used for multiplayer
var cards_played_this_turn = []
var must_draw_to_end_turn = true

var card_scene := preload("res://Card.tscn")
var cards = []
var deck: Array = []

func _process(_delta: float) -> void:
	if is_my_turn:
		$Button.visible = true
	else:
		$Button.visible = false

#-------CARDS-------

var cat_tac = preload("res://cards/cat tac card.png")
var cat_alope = preload("res://cards/cat-alope card.png")
var combusting_cat = preload("res://cards/combusting cat card.png")	# Exploding Kitten
var commence_hostilities = preload("res://cards/commence hostilities card.png")
var deactivate = preload("res://cards/deactivate card.png")			# Defuse
var gay_cat = preload("res://cards/gay cat card.png")
var goatee_cat = preload("res://cards/goatee cat card.png")
var indulgence = preload("res://cards/indulgence card.png")
var no = preload("res://cards/no card.png")
var omit = preload("res://cards/omit card.png")
var rearrange = preload("res://cards/rearrange card.png")
var view_2050 = preload("res://cards/view 2050 card.png")
var yam_cat = preload("res://cards/yam cat with hair card.png")

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

#------deck contents-----
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
	deactivate: 2,			# 2 extra defuses in deck (1 per player starts in hand)
	combusting_cat: 1		# exploding kitten
}

func _ready():
	build_starting_hand_safe()
	add_card(deactivate)
	start_turn()

func start_turn():
	cards_played_this_turn.clear()
	is_my_turn = true
	print("Turn started")



# -------------------------
# SAFE FIRST HAND LOGIC
# -------------------------
func build_starting_hand_safe():
	var deck_no_bombs := []

	# Build deck but skip bomb + defuse
	for texture in deck_contents.keys():
		if texture == deactivate or texture == combusting_cat:
			continue
		var count = deck_contents[texture]
		for i in count:
			deck_no_bombs.append(texture)

	deck_no_bombs.shuffle()

	# This becomes the real deck temporarily
	deck = deck_no_bombs

	# Draw 7 cards FROM THE REAL DECK
	for i in 7:
		var card_texture = deck.pop_back()
		add_card(card_texture)

	# Now insert bomb + extra defuses into deck
	insert_bombs_and_defuses()

	# Now shuffle fully for the real match
	deck.shuffle()

func insert_bombs_and_defuses():
	# Add ALL defuses except the one you give to the player
	for i in deck_contents[deactivate]:
		deck.append(deactivate)

	# Add the exploding kitten
	deck.append(combusting_cat)

func discard_card(texture: Texture2D):
	# Add to history
	discard_pile.append(texture)

	# Show most recently discarded card
	discard_area.texture = texture


# -------------------------
# NORMAL DECK BUILD
# -------------------------
func build_deck():
	deck.clear()

	for texture in deck_contents.keys():
		var count = deck_contents[texture]
		for i in count:
			deck.append(texture)

	deck.shuffle()


func draw_card():
	if not is_my_turn:
		return
	if bomb_drawn:
		print("You must deal with the bomb first! Play a Defuse.")
		return
	if deck.is_empty():
		print("Deck is empty!")
		return
	var card_texture = deck.pop_back()
	add_card(card_texture)

	if card_texture == combusting_cat:
		handle_bomb_draw(card_texture)
		return
	end_turn()


func handle_bomb_draw(texture: Texture2D):
	print("!!! You drew the EXPLODING KITTEN !!!")
	bomb_drawn = true
	pending_bomb_texture = texture
	if not has_defuse_in_hand():
		print("No defuse... YOU LOSE.")
		return
	print("You must play a Defuse to survive!")

func has_defuse_in_hand() -> bool:
	for card in cards:
		var tex: Texture2D = card.texture
		if card_types[tex] == "deactivate":
			return true
	return false

func end_turn():
	is_my_turn = false
	print("Turn ended")
	await get_tree().create_timer(0.3).timeout
	start_turn()

func add_card(texture: Texture2D):
	var card = card_scene.instantiate()
	card.texture = texture
	card.connect("card_played", Callable(self, "_on_card_played"))
	add_child(card)
	cards.append(card)
	update_card_positions()

func can_play_card(type: String) -> bool:

	if type == "combusting_cat":
		print("You cannot play the Exploding Kitten directly!")
		return false

	if bomb_drawn:
		if type == "deactivate":
			return true
		print("You must play a Defuse to survive!")
		return false

	if type == "deactivate":
		print("You cannot play a Defuse right now.")
		return false

	if type.begins_with("cat_"):
		var cats_in_hand := count_cat_in_hand(type)
		var played_this_turn := 0
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
	return true


func handle_defuse_played():
	print("Defuse used! Bomb avoided.")

	var insert_position = randi() % (deck.size() + 1)
	deck.insert(insert_position, pending_bomb_texture)

	print("Bomb inserted back into deck at random position.")

	bomb_drawn = false
	pending_bomb_texture = null

	end_turn()


func count_cat_in_hand(type: String) -> int:
	var count := 0
	for card in cards:
		var tex: Texture2D = card.texture
		var t: String = card_types[tex]
		if t == type:
			count += 1
	return count


func _on_card_played(card):
	if not is_my_turn:
		print("Can't play cards when it's not your turn!")
		return

	var tex: Texture2D = card.texture
	var type: String = card_types[tex]

	if not can_play_card(type):
		return

	print("Card played:", type)
	cards_played_this_turn.append(type)

	# Remove from hand
	cards.erase(card)
	card.queue_free()
	update_card_positions()

	# --- DEFUSE HANDLING ---
	if bomb_drawn and type == "deactivate":
		for c in cards:
			var tex2: Texture2D = c.texture
			if card_types[tex2] == "combusting_cat":
				cards.erase(c)
				c.queue_free()
				break

		update_card_positions()
		handle_defuse_played()
		return  # VERY IMPORTANT

	# --- ADD THIS BACK ---
	handle_card_effect(type)




func handle_card_effect(type):
	# CAT COMBOS
	if type.begins_with("cat_"):
		handle_cat_play(type)
		return
	match type:

		"commence_hostilities":   # ATTACK
			handle_attack()
		"omit":   # SKIP
			handle_skip()
		"no":    # NOPE
			handle_nope()
		"indulgence":   # FAVOR
			handle_favor()
		"view_2050":   # SEE THE FUTURE
			handle_see_future()
		"rearrange":   # SHUFFLE
			handle_shuffle()
		"combusting_cat":
			print("Bomb card effect processed earlier — should not be here.")
		"deactivate":
			print("Defuse already handled.")

func handle_attack():
	print("ATTACK played! Opponent must now take TWO turns.")
	# TODO: multiplayer turn system later
	# For now: skip drawing and end turn
	end_turn()

func handle_skip():
	print("SKIP played! Ending turn without drawing.")
	end_turn()

func handle_nope():
	print("NOPE played! (Cancel effect not implemented yet — needs action history)")

func handle_favor():
	print("FAVOR played! Opponent must give you a card. (Not implemented yet)")

func handle_see_future():
	print("SEE THE FUTURE: Top 3 cards are:")
	var count: int = min(3, deck.size())
	for i in count:
		var tex: Texture2D = deck[deck.size() - 1 - i]
		var t: String = card_types[tex]
		print("   ", i + 1, ": ", t)


func handle_shuffle():
	print("Shuffling the deck...")
	deck.shuffle()
	print("Deck shuffled.")


func handle_cat_play(cat_type):
	var count := 0
	for c in cards_played_this_turn:
		if c == cat_type:
			count += 1

	if count == 2:
		print("TWO-OF-A-KIND activated for:", cat_type)
		activate_two_cat_combo(cat_type)

	elif count == 3:
		print("THREE-OF-A-KIND activated for:", cat_type)
		activate_three_cat_combo(cat_type)

	# If you want: 5 unique cats combo here
func activate_two_cat_combo(cat_type):
	print("Steal a random card from opponent (not implemented yet)")


func activate_three_cat_combo(cat_type):
	print("Steal a specific card of your choice (not implemented yet)")



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


func _on_button_pressed() -> void:
	draw_card()
