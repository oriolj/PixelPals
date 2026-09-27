extends Control
## One game card: a rounded frame, the cover (or a generated placeholder), and
## the title in large type. `focus` (0..1, set by the carousel every frame)
## drives the glow, the border and the brightness. Coming-soon cards are greyed
## with a ribbon; the power card draws a power symbol and a hold ring.

const Pal := preload("res://scripts/palette.gd")

const COVER := Vector2(640, 360)
const PAD := 18.0
const TITLE_H := 112.0
const SIZE := Vector2(COVER.x + PAD * 2, COVER.y + PAD * 2 + TITLE_H)
const RADIUS := 30
## Pixel-art covers (native width up to this) are pre-scaled with nearest
## filtering by a whole factor, then drawn with mipmapped linear filtering:
## sharp pixels at the focused size (exactly 2x for 320x180), no shimmer when small.
const PIXEL_MAX_W := 640

const ROUNDED_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(640.0, 360.0);
uniform float radius = 22.0;
uniform float grey = 0.0;
uniform float bright = 1.0;
void fragment() {
	vec4 c = COLOR;
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = clamp(0.5 - d, 0.0, 1.0);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(l * 0.75 + 0.12), grey) * bright;
	COLOR = vec4(c.rgb, c.a * a);
}
"""

static var _shader: Shader

var entry: Dictionary = {}
var kind := "game"  # "game" | "soon" | "power"
var focus := 0.0
var recent := false
var hold := 0.0  # power card hold progress 0..1
var title_font: Font

var _style := StyleBoxFlat.new()
var _panel: Panel
var _cover: TextureRect
var _mat: ShaderMaterial
var _title: Label
var _pulse := 0.0
var _spinner: Control
var _power_icon: Control
var _spin_t := 0.0


func setup(e: Dictionary, font: Font) -> void:
	entry = e
	title_font = font
	kind = e.get("kind", "game" if e.get("playable", false) else "soon")
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_style.bg_color = Pal.SLATE
	_style.set_corner_radius_all(RADIUS)
	_style.set_border_width_all(6)
	_style.border_color = Pal.GREY_BLUE
	_style.shadow_size = 18
	_style.shadow_offset = Vector2(0, 10)
	_style.shadow_color = Color(0, 0, 0, 0.45)
	_style.anti_aliasing = true
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.size = SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	if _shader == null:
		_shader = Shader.new()
		_shader.code = ROUNDED_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("size", COVER)
	_mat.set_shader_parameter("radius", float(RADIUS - 10))
	_cover = TextureRect.new()
	_cover.position = Vector2(PAD, PAD)
	_cover.size = COVER
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_SCALE
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cover.material = _mat
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	match kind:
		"power":
			_cover.texture = _solid(Pal.NIGHT)
		_:
			var tex := load_cover(entry.get("cover", ""))
			_cover.texture = tex if tex else placeholder(entry.get("slug", "?"))
	if kind != "power" and entry.get("cover", "") == "":
		_add_initial()
	if kind == "power":
		_power_icon = Control.new()
		_power_icon.size = SIZE
		_power_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_power_icon.draw.connect(_draw_power)
		add_child(_power_icon)

	_title = Label.new()
	_title.text = entry.get("title", "")
	_title.position = Vector2(PAD, PAD + COVER.y + 4)
	_title.size = Vector2(COVER.x, TITLE_H - 8)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.clip_text = false
	_title.add_theme_font_override("font", font)
	var fs := 54
	while fs > 30 and font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > COVER.x - 24:
		fs -= 2
	_title.add_theme_font_size_override("font_size", fs)
	_title.add_theme_color_override("font_color", Pal.WHITE)
	_title.add_theme_color_override("font_outline_color", Pal.NIGHT)
	_title.add_theme_constant_override("outline_size", 10)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	if kind == "soon":
		_mat.set_shader_parameter("grey", 1.0)
		_add_badge("Coming soon", Pal.ORANGE, Pal.NIGHT, Vector2(COVER.x + PAD - 16, PAD + 16), true)
	queue_redraw()


func set_recent(on: bool) -> void:
	recent = on
	if on:
		_add_badge("Last played", Pal.GREEN, Pal.NIGHT, Vector2(PAD + 16, PAD + 16), false)


# ------------------------------------------------------------ cover textures

## Cover PNG from its bytes (no import cache involved). null when missing.
static func load_cover(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() <= PIXEL_MAX_W:
		var k := ceili(1280.0 / img.get_width())
		img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A generated 16:9 card for a game without cover.png: a two-colour gradient
## (picked from the slug) with soft polka dots. The card adds the initial.
static func placeholder(slug: String) -> Texture2D:
	var pairs := [[Pal.NAVY, Pal.BLUE], [Pal.PURPLE, Pal.RED], [Pal.TEAL, Pal.GREEN_DARK],
		[Pal.RED, Pal.ORANGE], [Pal.BLUE, Pal.SKY], [Pal.SLATE, Pal.TEAL]]
	var pair: Array = pairs[absi(slug.hash()) % pairs.size()]
	var w := 640
	var h := 360
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var a: Color = pair[0]
	var b: Color = pair[1]
	for y in h:
		for x in w:
			var t := clampf((x * 0.35 + y) / (w * 0.35 + h), 0.0, 1.0)
			var c := a.lerp(b, t)
			# Polka dots on a 40 px grid, every other row shifted.
			var gx := float(x % 40) - 20.0
			var gy := float(y % 40) - 20.0
			if (y / 40) % 2 == 1:
				gx = float((x + 20) % 40) - 20.0
			if gx * gx + gy * gy < 36.0:
				c = c.lerp(Pal.WHITE, 0.12)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _solid(c: Color) -> Texture2D:
	var img := Image.create(16, 9, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _add_initial() -> void:
	var l := Label.new()
	l.text = String(entry.get("title", "?")).substr(0, 1).to_upper()
	l.position = Vector2(PAD, PAD)
	l.size = COVER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", title_font)
	l.add_theme_font_size_override("font_size", 220)
	l.add_theme_color_override("font_color", Color(Pal.WHITE, 0.92))
	# A drop shadow, not an outline: big outlines show the variable font's
	# overlapping contours as ghost strokes inside the letter.
	l.add_theme_color_override("font_shadow_color", Color(Pal.NIGHT, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _add_badge(text: String, bg: Color, fg: Color, at: Vector2, right_aligned: bool) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font)
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", fg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	sb.shadow_size = 6
	sb.shadow_color = Color(0, 0, 0, 0.35)
	l.add_theme_stylebox_override("normal", sb)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	# The label has no size until the next layout pass: measure the text.
	var w := title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 36.0
	l.position = at - Vector2(w if right_aligned else 0.0, 0)


# ------------------------------------------------------------ spinner (import)

func show_spinner(on: bool) -> void:
	if on and _spinner == null:
		_spinner = Control.new()
		_spinner.position = Vector2(PAD, PAD)
		_spinner.size = COVER
		_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spinner.draw.connect(_draw_spinner)
		add_child(_spinner)
	if _spinner:
		_spinner.visible = on


func _draw_spinner() -> void:
	var c := COVER / 2
	_spinner.draw_rect(Rect2(Vector2.ZERO, COVER), Color(Pal.NIGHT, 0.6))
	for i in 10:
		var ang := TAU * i / 10.0 + _spin_t * 5.0
		var t := float(i) / 10.0
		_spinner.draw_circle(c + Vector2.from_angle(ang) * 70.0, 6.0 + 8.0 * t, Color(Pal.YELLOW, 0.25 + 0.75 * t), true, -1.0, true)


# ------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_pulse += delta
	var f := clampf(focus, 0.0, 1.0)
	var glow := f * (0.8 + 0.2 * sin(_pulse * 3.2))
	var base_border := Pal.GREY_BLUE if kind != "power" else Pal.RED.darkened(0.2)
	var hi := Pal.YELLOW if kind != "power" else Pal.RED.lightened(0.25)
	_style.border_color = base_border.lerp(hi, f)
	_style.set_border_width_all(int(lerpf(5.0, 9.0, f)))
	_style.shadow_size = int(lerpf(16.0, 46.0, glow))
	_style.shadow_offset = Vector2(0, lerpf(12.0, 0.0, f))
	_style.shadow_color = Color(0, 0, 0, 0.45).lerp(Color(hi, 0.55), glow)
	_style.bg_color = Pal.SLATE.lerp(Pal.NAVY, f)
	var bright := lerpf(0.62, 1.0, f)
	_mat.set_shader_parameter("bright", bright)
	_title.modulate = Color(1, 1, 1, lerpf(0.72, 1.0, f))
	if _spinner and _spinner.visible:
		_spin_t += delta
		_spinner.queue_redraw()
	if _power_icon:
		_power_icon.queue_redraw()


func _draw_power() -> void:
	# Power symbol in the cover area, with the hold ring around it.
	var c := Vector2(PAD, PAD) + COVER / 2
	var r := 92.0
	var col := Pal.RED.lightened(0.15).lerp(Pal.WHITE, 0.2 * focus)
	_power_icon.draw_circle(c, r + 40, Color(Pal.RED, 0.10 + 0.08 * focus), true, -1.0, true)
	_power_icon.draw_arc(c, r, -PI / 2 + 0.6, -PI / 2 + TAU - 0.6, 48, col, 18.0, true)
	_power_icon.draw_line(c + Vector2(0, -r - 18), c + Vector2(0, -r * 0.2), col, 18.0, true)
	_power_icon.draw_circle(c + Vector2(0, -r - 18), 9.0, col, true, -1.0, true)
	_power_icon.draw_circle(c + Vector2(0, -r * 0.2), 9.0, col, true, -1.0, true)
	if hold > 0.0:
		_power_icon.draw_arc(c, r + 34, -PI / 2, -PI / 2 + TAU * hold, 64, Pal.YELLOW, 14.0, true)
