extends TextureRect
signal card_played(card)

func set_image(texture: Texture2D):
	self.texture = texture
var hovering = false
var viewing = false
func _on_mouse_entered() -> void:
	hovering = true
	viewing = false
	scale = Vector2(1.05,1.05)
	z_index = 4
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("rightmouse") and hovering and not viewing:
		viewing = true
		scale = Vector2(3,3)
		position.y -= 120

	if Input.is_action_just_pressed("leftmouse"):
		if hovering and not viewing:
			emit_signal("card_played", self)



func _on_mouse_exited() -> void:
	if viewing:
		position.y += 120
	viewing = false
	hovering = false
	scale = Vector2(1,1)
	z_index = 0
