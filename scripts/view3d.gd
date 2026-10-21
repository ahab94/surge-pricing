extends Node3D
## The angled 3D view. The game still runs in 2D (city.gd, car.gd and
## traffic.gd work in flat pixel coordinates); this node only *draws* that
## world in 3D, every frame, from the game's state. Keeping the simulation 2D
## means the autopilot, tests and replays don't change at all.
##
## 2D (x, y) pixels map to 3D (x, height, z) units: x/S, y, y/S. Up is +Y.
##
## Godot 3D basics used here:
## - A MeshInstance3D shows a Mesh. Meshes are built in code with SurfaceTool
##   (static city) or ImmediateMesh (things redrawn every frame).
## - A material says how a surface looks. `vertex_color_use_as_albedo` lets
##   one material colour a whole city: each vertex carries its own colour.
## - Godot treats clockwise triangles as front faces. Culling is off on the
##   city material, so winding doesn't matter. Normals are set by hand for lighting.
## - Camera3D.look_at() aims the camera; a DirectionalLight3D is the sun and
##   casts the shadows.

const City := preload("res://scripts/city.gd")
const Riders := preload("res://scripts/riders.gd")

const S := 32.0                 # pixels per 3D unit (a 128 px tile = 4 units)
const PITCH := deg_to_rad(60.0) # camera tilt above the horizon
const SIDEWALK_Y := 0.15
const WATER_Y := -0.45
const BANDS := [Color("4dbb5f"), Color("ffd23f"), Color("ff4d6d")]
const FACADES := [Color("e8875f"), Color("f0b75a"), Color("8fb8de"), Color("b39ddb"),
		Color("e57373"), Color("7fc8a9"), Color("f4e1a1"), Color("a1887f"), Color("cfd8dc")]
const ROUTE := Color("37b7ff")
const SURGE := Color("ff4fa3")

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var _city
var _city_root: Node3D
var _car: Node3D
var _vehicles := {}             # traffic id -> {node, honk, lights}
var _siren_mats: Array = []     # [red, blue, dark] for flashing light bars
var _fx_mesh: ImmediateMesh
var _beams: Array = []          # pooled light beams over requests and the drop-off
var _people: Array = []
var _arrow: MeshInstance3D
var _arrow_mat: StandardMaterial3D
var _popups: Array = []         # pooled Label3Ds
var _mats := {}
var _cam_target := Vector3.ZERO
var _menu_angle := 0.0
var _t := 0.0
var _smooth_pos := Vector2.ZERO  # the car's position between physics ticks


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 400.0
	add_child(camera)
	camera.make_current()

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fd0f5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 1.0)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_fx_mesh = ImmediateMesh.new()
	var fx := MeshInstance3D.new()
	fx.mesh = _fx_mesh
	fx.material_override = _unshaded(Color.WHITE, true, true)
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fx)

	_arrow = MeshInstance3D.new()
	_arrow.mesh = _arrow_mesh()
	_arrow_mat = _unshaded(Color("57e36b"), false, false)
	_arrow_mat.no_depth_test = true   # always visible, even behind a building
	_arrow_mat.render_priority = 2
	_arrow.material_override = _arrow_mat
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)

	for i in 8:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 72
		l.outline_size = 18
		l.outline_modulate = Color("2a2d36")
		l.pixel_size = 0.012
		l.render_priority = 3
		l.outline_render_priority = 2
		l.visible = false
		add_child(l)
		_popups.append(l)


# ---------------------------------------------------------------- helpers

func p3(v: Vector2, y := 0.0) -> Vector3:
	return Vector3(v.x / S, y, v.y / S)


func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.8
		_mats[key] = m
	return _mats[key]


func _unshaded(col: Color, transparent: bool, vertex_colors: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = true
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A box without a bottom. Normals point outwards.
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color, top_col := Color(0, 0, 0, 0)) -> void:
	var top := col if top_col.a == 0.0 else top_col
	_face(st, [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Vector3.UP, top)
	_face(st, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Vector3.BACK, col)
	_face(st, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)], Vector3.FORWARD, col)
	_face(st, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)], Vector3.RIGHT, col)
	_face(st, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)], Vector3.LEFT, col)


func _face(st: SurfaceTool, v: Array, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[i])


func _flat(st: SurfaceTool, r: Rect2, y: float, col: Color) -> void:
	_face(st, [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y),
			Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)], Vector3.UP, col)


func _hash(t: Vector2i, salt := 0) -> int:
	return absi((t.x * 73856093) ^ (t.y * 19349663) ^ (salt * 83492791))


# ---------------------------------------------------------------- the static city

## Builds the city once. Every shift uses the same map, so it's kept between shifts.
func build_city(city) -> void:
	if _city_root != null:
		return
	_city = city
	_city_root = Node3D.new()
	add_child(_city_root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile := City.TILE / S
	var trees: Array = []
	for y in city.h:
		for x in city.w:
			var t := Vector2i(x, y)
			var r := Rect2(Vector2(x, y) * tile, Vector2(tile, tile))
			_build_tile(st, city, t, r, tile, trees)
	# Ground outside the map, so the camera never sees the void.
	_flat(st, Rect2(-60, -60, city.w * tile + 120, city.h * tile + 120), WATER_Y - 0.3, Color("1d5a85"))   # the harbour around the city
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true   # our colours are ordinary (sRGB) hex colours
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_city_root.add_child(mi)
	for p in trees:
		_tree(p)
	_build_water(city, tile)
	for letter in city.stops:
		var c: Vector3 = p3(city.center(city.stops[letter]))
		var l := Label3D.new()
		l.text = City.STOP_NAMES[letter]
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 48
		l.outline_size = 12
		l.pixel_size = 0.01
		l.modulate = Color("fff8e7")
		l.outline_modulate = Color(0, 0, 0, 0.6)
		l.position = c + Vector3(0, 2.6, -1.4)
		_city_root.add_child(l)


func _build_tile(st: SurfaceTool, city, t: Vector2i, r: Rect2, tile: float, trees: Array) -> void:
	var c: String = city.cell(t)
	var k := tile / City.D            # design px (96 grid) -> units
	match c:
		"#":
			_flat(st, r, SIDEWALK_Y, Color("c9c2b4"))
			_building(st, city, t, r, k)
		",", "T", "h":
			var g := Color("78c25f").darkened(0.06 * (_hash(t) % 3))
			_flat(st, r, 0.03, g)
			if c == "T":
				trees.append(Vector3(r.get_center().x, 0, r.get_center().y))
			elif c == "h":
				_house(st, t, r, k)
		"~":
			# The bank: stone walls down to the water wherever land meets it.
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if city.cell(t + d) != "~":
					_bank(st, r, d)
		"F":
			_flat(st, r, 0.0, Color("8d8f99"))
			if city.cell(t + Vector2i(-1, 0)) != "F" and city.cell(t + Vector2i(0, -1)) != "F":
				_fountain(Vector3(r.end.x, 0, r.end.y), tile)
		_:
			_road(st, city, t, r, k)


func _road(st: SurfaceTool, city, t: Vector2i, r: Rect2, k: float) -> void:
	var c: String = city.cell(t)
	_flat(st, r, 0.0, Color("3d4250"))
	var road_l: bool = city.is_road(t + Vector2i(-1, 0))
	var road_r: bool = city.is_road(t + Vector2i(1, 0))
	var road_u: bool = city.is_road(t + Vector2i(0, -1))
	var road_d: bool = city.is_road(t + Vector2i(0, 1))
	var paint := Color("f2d24b")
	if c != "^":
		if road_l and road_r and not road_u and not road_d:
			for i in 2:
				_flat(st, Rect2(r.position.x + (8 + i * 48) * k, r.get_center().y - 2 * k, 30 * k, 4 * k), 0.01, paint)
		elif road_u and road_d and not road_l and not road_r:
			for i in 2:
				_flat(st, Rect2(r.get_center().x - 2 * k, r.position.y + (8 + i * 48) * k, 4 * k, 30 * k), 0.01, paint)
	# Bridges: railings along the water.
	var rail := Color("b0b6c2")
	if city.cell(t + Vector2i(-1, 0)) == "~":
		_box(st, Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x + 0.15, 0.5, r.end.y), rail)
	if city.cell(t + Vector2i(1, 0)) == "~":
		_box(st, Vector3(r.end.x - 0.15, 0, r.position.y), Vector3(r.end.x, 0.5, r.end.y), rail)
	if c == "^":
		_ramp(st, city, t, r)
	if City.STOP_NAMES.has(c):
		# A pickup sign: a post with a pink ball on top.
		var post := Vector3(r.end.x - 0.35, 0, r.position.y + 0.35)
		_box(st, post - Vector3(0.05, 0, 0.05), post + Vector3(0.05, 1.6, 0.05), Color("d9d9d9"))
		_box(st, post + Vector3(-0.25, 1.6, -0.25), post + Vector3(0.25, 2.1, 0.25), Color("ff4fa3"))


## A wedge rising toward the water (or north, on dry land).
func _ramp(st: SurfaceTool, city, t: Vector2i, r: Rect2) -> void:
	var toward_south: bool = city.cell(t + Vector2i(0, 1)) == "~"
	var lo_z := r.end.y if not toward_south else r.position.y
	var hi_z := r.position.y + 0.4 if not toward_south else r.end.y - 0.4
	var h := 0.9
	var x0 := r.position.x + 0.25
	var x1 := r.end.x - 0.25
	var yellow := Color("ffd23f")
	var a := Vector3(x0, 0, lo_z)
	var b := Vector3(x1, 0, lo_z)
	var c := Vector3(x1, h, hi_z)
	var d := Vector3(x0, h, hi_z)
	var n := (c - b).cross(Vector3(1, 0, 0)).normalized()
	if n.y < 0:
		n = -n
	_face(st, [a, b, c, d], n, yellow)
	# Black chevrons painted on the slope.
	for i in 3:
		var f0 := 0.2 + i * 0.27
		var f1 := f0 + 0.1
		var p0 := a.lerp(d, f0) + Vector3(0, 0.02, 0)
		var p1 := b.lerp(c, f0) + Vector3(0, 0.02, 0)
		var p2 := b.lerp(c, f1) + Vector3(0, 0.02, 0)
		var p3_ := a.lerp(d, f1) + Vector3(0, 0.02, 0)
		_face(st, [p0, p1, p2, p3_], n, Color("2a2d36"))
	_face(st, [Vector3(x0, h, hi_z), Vector3(x1, h, hi_z), Vector3(x1, 0, hi_z), Vector3(x0, 0, hi_z)],
			Vector3(0, 0, 1 if toward_south else -1), yellow.darkened(0.3))
	_face(st, [a, d, Vector3(x0, 0, hi_z), a], Vector3.LEFT, yellow.darkened(0.2))
	_face(st, [b, c, Vector3(x1, 0, hi_z), b], Vector3.RIGHT, yellow.darkened(0.2))


func _bank(st: SurfaceTool, r: Rect2, d: Vector2i) -> void:
	var stone := Color("8a8f99")
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	if d.x == 1:
		x0 = x1
	elif d.x == -1:
		x1 = x0
	elif d.y == 1:
		z0 = z1
	else:
		z1 = z0
	_face(st, [Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x1, WATER_Y, z1), Vector3(x0, WATER_Y, z0)],
			Vector3(-d.x, 0, -d.y), stone)


func _building(st: SurfaceTool, city, t: Vector2i, r: Rect2, k: float) -> void:
	# Each 2x2 chunk is one building. Height grows toward the plaza (downtown).
	var chunk := Vector2i(t.x / 2, t.y / 2)
	var hk := _hash(chunk, 7)
	var downtown := 1.0 - clampf(Vector2(t).distance_to(Vector2(19, 11)) / 22.0, 0.0, 1.0)
	var h := 1.1 + float(hk % 5) * 0.3 + downtown * 2.4
	var wall: Color = FACADES[hk % FACADES.size()]
	var roof := wall.darkened(0.12)
	var inset := 10.0 * k
	var lo := Vector3(r.position.x, SIDEWALK_Y, r.position.y)
	var hi := Vector3(r.end.x, h, r.end.y)
	var open := {}
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		open[d] = city.cell(t + d) != "#"
	if open[Vector2i(-1, 0)]:
		lo.x += inset
	if open[Vector2i(1, 0)]:
		hi.x -= inset
	if open[Vector2i(0, -1)]:
		lo.z += inset
	if open[Vector2i(0, 1)]:
		hi.z -= inset
	_box(st, lo, hi, wall, roof)
	# Window bands on street-facing walls.
	var glass := Color("33475f")
	var y := 0.7
	while y + 0.5 < h:
		if open[Vector2i(0, 1)]:
			_face(st, [Vector3(lo.x + 0.25, y, hi.z + 0.02), Vector3(hi.x - 0.25, y, hi.z + 0.02),
					Vector3(hi.x - 0.25, y + 0.38, hi.z + 0.02), Vector3(lo.x + 0.25, y + 0.38, hi.z + 0.02)], Vector3.BACK, glass)
		if open[Vector2i(0, -1)]:
			_face(st, [Vector3(lo.x + 0.25, y, lo.z - 0.02), Vector3(hi.x - 0.25, y, lo.z - 0.02),
					Vector3(hi.x - 0.25, y + 0.38, lo.z - 0.02), Vector3(lo.x + 0.25, y + 0.38, lo.z - 0.02)], Vector3.FORWARD, glass)
		if open[Vector2i(1, 0)]:
			_face(st, [Vector3(hi.x + 0.02, y, lo.z + 0.25), Vector3(hi.x + 0.02, y, hi.z - 0.25),
					Vector3(hi.x + 0.02, y + 0.38, hi.z - 0.25), Vector3(hi.x + 0.02, y + 0.38, lo.z + 0.25)], Vector3.RIGHT, glass)
		if open[Vector2i(-1, 0)]:
			_face(st, [Vector3(lo.x - 0.02, y, lo.z + 0.25), Vector3(lo.x - 0.02, y, hi.z - 0.25),
					Vector3(lo.x - 0.02, y + 0.38, hi.z - 0.25), Vector3(lo.x - 0.02, y + 0.38, lo.z + 0.25)], Vector3.LEFT, glass)
		y += 0.8
	# Rooftop clutter.
	match _hash(t, 3) % 5:
		0, 1:
			var p := Vector3(lo.x + 0.8, h, lo.z + 0.8)
			_box(st, p, p + Vector3(0.7, 0.4, 0.5), Color("dcdcdc"))
		2:
			var p := Vector3(lo.x + 1.0, h, lo.z + 1.2)
			_box(st, p, p + Vector3(0.3, 0.9, 0.3), Color("9e9e9e"))


func _house(st: SurfaceTool, t: Vector2i, r: Rect2, k: float) -> void:
	var inset := 14.0 * k
	var lo := Vector3(r.position.x + inset, 0.03, r.position.y + inset)
	var hi := Vector3(r.end.x - inset, 1.2, r.end.y - inset)
	_box(st, lo, hi, Color("f3ead8"))
	var roof: Color = [Color("c0504d"), Color("4f81bd"), Color("8064a2"), Color("f79646")][_hash(t) % 4]
	var mid_z := (lo.z + hi.z) * 0.5
	var top := hi.y + 0.9
	var o := 0.15   # eaves
	_face(st, [Vector3(lo.x - o, hi.y, lo.z - o), Vector3(hi.x + o, hi.y, lo.z - o), Vector3(hi.x + o, top, mid_z),
			Vector3(lo.x - o, top, mid_z)], Vector3(0, 0.7, -0.7).normalized(), roof)
	_face(st, [Vector3(lo.x - o, hi.y, hi.z + o), Vector3(hi.x + o, hi.y, hi.z + o), Vector3(hi.x + o, top, mid_z),
			Vector3(lo.x - o, top, mid_z)], Vector3(0, 0.7, 0.7).normalized(), roof.darkened(0.15))
	for x in [lo.x, hi.x]:
		_face(st, [Vector3(x, hi.y, lo.z), Vector3(x, hi.y, hi.z), Vector3(x, top - 0.05, mid_z), Vector3(x, hi.y, lo.z)],
				Vector3.RIGHT if x == hi.x else Vector3.LEFT, Color("f3ead8"))
	_box(st, Vector3(hi.x - 0.7, hi.y, lo.z + 0.3), Vector3(hi.x - 0.4, top + 0.2, lo.z + 0.6), Color("7a5c4a"))


func _tree(p: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.2
	cyl.height = 1.0
	cyl.radial_segments = 6
	trunk.mesh = cyl
	trunk.material_override = _mat(Color("7a5c4a"))
	trunk.position = p + Vector3(0, 0.5, 0)
	_city_root.add_child(trunk)
	var top := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 1.8
	sph.radial_segments = 8
	sph.rings = 4
	top.mesh = sph
	top.material_override = _mat(Color("3f8f3a"))
	top.position = p + Vector3(0, 1.7, 0)
	_city_root.add_child(top)


func _fountain(c: Vector3, tile: float) -> void:
	var basin := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = tile * 0.92
	cyl.bottom_radius = tile * 0.95
	cyl.height = 0.5
	basin.mesh = cyl
	basin.material_override = _mat(Color("b8b2a6"))
	basin.position = c + Vector3(0, 0.25, 0)
	_city_root.add_child(basin)
	var water := MeshInstance3D.new()
	var w := CylinderMesh.new()
	w.top_radius = tile * 0.78
	w.bottom_radius = tile * 0.78
	w.height = 0.1
	water.mesh = w
	var wm := _mat(Color("3b9fd6")).duplicate() as StandardMaterial3D
	wm.roughness = 0.25
	water.material_override = wm
	water.position = c + Vector3(0, 0.48, 0)
	_city_root.add_child(water)
	var jet := MeshInstance3D.new()
	var j := CylinderMesh.new()
	j.top_radius = 0.1
	j.bottom_radius = 0.5
	j.height = 2.2
	jet.mesh = j
	jet.material_override = _unshaded(Color(0.85, 0.95, 1.0, 0.7), true, false)
	jet.position = c + Vector3(0, 1.5, 0)
	_city_root.add_child(jet)


## Water is one sunken, shiny surface per water tile row run.
func _build_water(city, tile: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in city.h:
		for x in city.w:
			if city.cell(Vector2i(x, y)) == "~":
				_flat(st, Rect2(Vector2(x, y) * tile, Vector2(tile, tile)), WATER_Y, Color("3b9fd6"))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a7fb8")
	m.roughness = 0.4
	mi.material_override = m
	_city_root.add_child(mi)


# ---------------------------------------------------------------- cars

## A low-poly car: body, glass cabin, wheels. Faces +X (the 2D heading).
func make_car(col: Color, player: bool) -> Node3D:
	var root := Node3D.new()
	var parts := [
		[Vector3(1.5, 0.42, 0.82), Vector3(0, 0.38, 0), col],
		[Vector3(0.82, 0.34, 0.72), Vector3(-0.08, 0.76, 0), Color("2c3e5c")],
		[Vector3(0.6, 0.06, 0.74), Vector3(-0.1, 0.95, 0), col.lightened(0.15)],
	]
	if player:
		parts.append([Vector3(0.3, 0.2, 0.3), Vector3(-0.1, 1.08, 0), Color("ff4fa3")])
	for p in parts:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = p[0]
		mi.mesh = b
		mi.position = p[1]
		var m := _mat(p[2])
		if player and p == parts[0]:
			# X-ray: a second pass with no depth test draws the car's silhouette
			# through buildings, so you never lose your car behind a tower.
			m = m.duplicate() as StandardMaterial3D
			var ghost := _unshaded(Color(0.6, 0.9, 0.3, 0.22), true, false)
			ghost.no_depth_test = true
			ghost.render_priority = -1
			m.next_pass = ghost
		if player and p[2] == Color("ff4fa3"):
			m = m.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission = Color("ff4fa3")
		mi.material_override = m
		root.add_child(mi)
	for wx in [-0.48, 0.48]:
		for wz in [-0.42, 0.42]:
			var w := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.36, 0.3, 0.12)
			w.mesh = b
			w.position = Vector3(wx, 0.15, wz)
			w.material_override = _mat(Color("1d1f26"))
			root.add_child(w)
	for z in [-0.28, 0.28]:
		var light := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.04, 0.1, 0.16)
		light.mesh = b
		light.position = Vector3(0.76, 0.45, z)
		light.material_override = _unshaded(Color("fff3a0"), false, false)
		root.add_child(light)
	return root


## Called at the start of each shift: fresh traffic, weather.
func on_level(game) -> void:
	build_city(game.city)
	if _car == null:
		_car = make_car(Color("9be24a"), true)
		add_child(_car)
	for id in _vehicles:
		_vehicles[id].node.queue_free()
		_vehicles[id].honk.queue_free()
	_vehicles.clear()
	var rain: bool = game.level.rain
	sun.light_energy = 0.45 if rain else 0.8
	env.background_color = Color("5d6b80") if rain else Color("8fd0f5")
	env.ambient_light_color = Color(0.7, 0.75, 0.9) if rain else Color(0.85, 0.88, 1.0)
	env.fog_enabled = rain
	env.fog_light_color = Color("7d8aa0")
	env.fog_density = 0.012
	_car.visible = true
	_cam_target = p3(game.car.position)


## Where the top of the car is on screen, for the speech bubble.
func car_screen_pos() -> Vector2:
	if _car == null or not _car.visible:
		return camera.unproject_position(p3(_smooth_pos, 1.5))
	return camera.unproject_position(_car.position + Vector3(0, 1.5, 0))


## Physics runs at a fixed 60 ticks a second, but screens refresh at their
## own rate (120 Hz, or uneven in a browser). Drawing things exactly where the
## last tick left them makes them hop; instead blend between the previous and
## the current tick by how far we are into the next one.
func car_pos(game) -> Vector2:
	var car = game.car
	return car.prev_pos.lerp(car.position, Engine.get_physics_interpolation_fraction())


# ---------------------------------------------------------------- traffic

## Traffic comes and goes (special events), so nodes are matched to vehicles
## by id every frame: new ids get a model, vanished ids are freed.
func _sync_traffic(game) -> void:
	var seen := {}
	var flash := int(_t * 7.0) % 2 == 0
	for npc in game.traffic.cars:
		seen[npc.id] = true
		if not _vehicles.has(npc.id):
			_vehicles[npc.id] = _make_vehicle(npc)
		var v: Dictionary = _vehicles[npc.id]
		var f := Engine.get_physics_interpolation_fraction()
		v.node.position = p3(npc.prev_pos.lerp(npc.pos, f))
		v.node.rotation = Vector3(0, -lerp_angle(npc.prev_angle, npc.angle, f), 0)
		v.honk.visible = npc.honk > 0.0
		v.honk.position = p3(npc.pos, 2.2)
		for i in v.lights.size():
			var on: bool = flash == (i % 2 == 0)
			v.lights[i].material_override = _siren_mats[i % 2] if on else _siren_mats[2]
	for id in _vehicles.keys():
		if not seen.has(id):
			_vehicles[id].node.queue_free()
			_vehicles[id].honk.queue_free()
			_vehicles.erase(id)


func _part(root: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(col)
	root.add_child(mi)
	return mi


func _wheels(root: Node3D, half_len: float, half_w: float) -> void:
	for wx in [-half_len, half_len]:
		for wz in [-half_w, half_w]:
			_part(root, Vector3(0.36, 0.3, 0.12), Vector3(wx, 0.15, wz), Color("1d1f26"))


## Models for each kind of vehicle, all facing +X like the player's car.
func _make_vehicle(npc: Dictionary) -> Dictionary:
	if _siren_mats.is_empty():
		for c in [Color("ff2a3a"), Color("2a6bff")]:
			var m := _unshaded(c, false, false)
			_siren_mats.append(m)
		_siren_mats.append(_mat(Color("3a3d48")))
	var col: Color = npc.color
	var glass := Color("2c3e5c")
	var root: Node3D
	var lights: Array = []
	match npc.kind:
		"ambulance":
			root = Node3D.new()
			_part(root, Vector3(1.4, 1.0, 0.86), Vector3(-0.22, 0.65, 0), col)
			_part(root, Vector3(0.5, 0.62, 0.84), Vector3(0.7, 0.46, 0), col)
			_part(root, Vector3(0.08, 0.3, 0.74), Vector3(0.93, 0.62, 0), glass)
			_part(root, Vector3(1.42, 0.14, 0.88), Vector3(-0.22, 0.55, 0), Color("e8343f"))
			_part(root, Vector3(0.36, 0.36, 0.06), Vector3(-0.3, 0.85, 0.44), Color("e8343f"))
			lights.append(_part(root, Vector3(0.18, 0.14, 0.3), Vector3(0.45, 1.22, -0.2), Color.RED))
			lights.append(_part(root, Vector3(0.18, 0.14, 0.3), Vector3(0.45, 1.22, 0.2), Color.BLUE))
			_wheels(root, 0.6, 0.42)
		"police":
			root = make_car(col, false)
			_part(root, Vector3(0.6, 0.3, 0.84), Vector3(0.05, 0.4, 0), Color("f2f2f2"))   # white doors
			lights.append(_part(root, Vector3(0.16, 0.12, 0.3), Vector3(-0.08, 1.04, -0.18), Color.RED))
			lights.append(_part(root, Vector3(0.16, 0.12, 0.3), Vector3(-0.08, 1.04, 0.18), Color.BLUE))
		"getaway":
			root = make_car(col, false)
			_part(root, Vector3(0.12, 0.08, 0.84), Vector3(-0.72, 0.78, 0), Color("17181c"))   # spoiler
			_part(root, Vector3(0.05, 0.2, 0.05), Vector3(-0.72, 0.66, -0.3), Color("17181c"))
			_part(root, Vector3(0.05, 0.2, 0.05), Vector3(-0.72, 0.66, 0.3), Color("17181c"))
		"trash":
			root = Node3D.new()
			_part(root, Vector3(0.7, 0.85, 0.92), Vector3(0.95, 0.55, 0), col.lightened(0.15))
			_part(root, Vector3(0.08, 0.34, 0.8), Vector3(1.3, 0.72, 0), glass)
			_part(root, Vector3(1.85, 1.2, 0.95), Vector3(-0.38, 0.75, 0), col)
			_part(root, Vector3(1.86, 0.1, 0.96), Vector3(-0.38, 1.0, 0), Color("ffd23f"))
			_part(root, Vector3(0.12, 0.9, 0.8), Vector3(-1.34, 0.65, 0), col.darkened(0.3))
			_wheels(root, 0.95, 0.46)
			_part(root, Vector3(0.36, 0.3, 0.12), Vector3(-0.2, 0.15, -0.46), Color("1d1f26"))
			_part(root, Vector3(0.36, 0.3, 0.12), Vector3(-0.2, 0.15, 0.46), Color("1d1f26"))
		"suv":
			root = Node3D.new()
			_part(root, Vector3(1.74, 0.55, 0.9), Vector3(0, 0.42, 0), col)
			_part(root, Vector3(1.1, 0.42, 0.84), Vector3(-0.2, 0.9, 0), Color("0c0d10"))
			for z in [-0.4, 0.4]:   # little flags on the front wings
				_part(root, Vector3(0.03, 0.4, 0.03), Vector3(0.75, 0.88, z), Color("c0c0c0"))
				_part(root, Vector3(0.22, 0.14, 0.02), Vector3(0.65, 1.0, z), Color("ffffff"))
				_part(root, Vector3(0.22, 0.05, 0.022), Vector3(0.65, 1.03, z), Color("e8343f"))
			_wheels(root, 0.58, 0.46)
		"bike":
			root = Node3D.new()
			_part(root, Vector3(0.9, 0.3, 0.22), Vector3(0, 0.3, 0), col)
			_part(root, Vector3(0.3, 0.5, 0.3), Vector3(-0.1, 0.7, 0), Color("1f2a44"))   # rider
			var helmet := _part(root, Vector3(0.24, 0.24, 0.24), Vector3(-0.08, 1.05, 0), Color("f2f2f2"))
			helmet.name = "Helmet"
			lights.append(_part(root, Vector3(0.1, 0.12, 0.1), Vector3(0.38, 0.55, -0.06), Color.BLUE))
			lights.append(_part(root, Vector3(0.1, 0.12, 0.1), Vector3(0.38, 0.55, 0.06), Color.RED))
		_:
			root = make_car(col, false)
	add_child(root)
	var l := Label3D.new()
	l.text = "HONK!"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 56
	l.outline_size = 14
	l.pixel_size = 0.01
	l.modulate = Color("ffd23f")
	l.outline_modulate = Color("2a2d36")
	l.visible = false
	add_child(l)
	return {"node": root, "honk": l, "lights": lights}


# ---------------------------------------------------------------- every frame

func sync(game, delta: float) -> void:
	_t += delta
	if game.car == null:
		_menu_camera(delta)
		return
	var car = game.car
	var lift: float = car.get_meta("lift", 0.0)
	_smooth_pos = car_pos(game)
	_car.position = p3(_smooth_pos, lift * 2.4)
	_car.visible = game.splash_hold <= 0.0   # sunk, waiting to respawn
	_car.rotation = Vector3(0, -lerp_angle(car.prev_heading, car.heading, Engine.get_physics_interpolation_fraction()), 0)
	# A little body roll in turns and pitch in the air sells the speed.
	_car.rotation.x = -car.steer * clampf(car.speed() / 700.0, 0, 1) * 0.12
	_car.rotation.z = (0.18 * (1.0 - 2.0 * clampf(1.0 - car.air / maxf(car.air_len, 0.01), 0, 1))) if car.air > 0.0 else 0.0
	_sync_traffic(game)
	_draw_fx(game)
	_place_arrow(game, lift)
	_place_popups(game)
	_follow_camera(game, delta)


func _follow_camera(game, delta: float) -> void:
	var car = game.car
	var ahead: Vector2 = (car.vel * 0.35).limit_length(220.0)
	var lim: Vector2 = game.city.size_px()
	var focus: Vector2 = (_smooth_pos + ahead) if game.splash_hold <= 0.0 else game.splash_pos
	if game.watch_special():
		var lead: Dictionary = game.watch_special()
		focus = lead.pos + lead.dir * 60.0
	# Only a small margin: past the edge is the harbour, which is fine to see,
	# and a bigger clamp pushes the car off-screen on the edge roads.
	focus = focus.clamp(Vector2(1.5, 1.5) * 128.0, lim - Vector2(1.5, 1.5) * 128.0)
	var want := p3(focus)
	_cam_target = _cam_target.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
	var rush := clampf(car.speed() / 720.0, 0.0, 1.0)
	var vp := get_viewport().get_visible_rect().size
	var portrait := vp.y > vp.x
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	camera.fov = 58.0 if portrait else 42.0
	var dist: float = (30.0 + 8.0 * rush) * game.cam_scale
	camera.position = _cam_target + Vector3(0, sin(PITCH), cos(PITCH)) * dist
	camera.look_at(_cam_target, Vector3.UP)


## On the menu, the camera slowly circles downtown.
func _menu_camera(delta: float) -> void:
	if _city == null:
		return
	if _car != null:
		_car.visible = false
	_fx_mesh.clear_surfaces()
	_arrow.visible = false
	for l in _popups:
		l.visible = false
	_menu_angle += delta * 0.08
	var c := p3(_city.size_px() * 0.5)
	camera.position = c + Vector3(cos(_menu_angle) * 55.0, 42.0, sin(_menu_angle) * 55.0)
	camera.look_at(c, Vector3.UP)


func _place_arrow(game, lift: float) -> void:
	var dir: Vector2 = game.arrow_dir
	_arrow.visible = dir != Vector2.ZERO
	if not _arrow.visible:
		return
	_arrow_mat.albedo_color = Color("57e36b") if not game.ride.is_empty() else Color("ffd23f")
	var base := p3(_smooth_pos, 2.6 + lift * 2.4 + 0.15 * sin(_t * 5.0))
	_arrow.position = base + Vector3(dir.x, 0, dir.y) * 1.2
	_arrow.rotation = Vector3(0, -dir.angle(), 0)


func _place_popups(game) -> void:
	for i in _popups.size():
		var l: Label3D = _popups[i]
		if i >= game.popups.size():
			l.visible = false
			continue
		var p: Dictionary = game.popups[i]
		l.visible = true
		l.text = p.text
		var a := clampf(p.t / 0.4, 0.0, 1.0)
		var c: Color = p.color
		l.modulate = Color(c, a)
		l.outline_modulate = Color(0.16, 0.18, 0.21, a)
		l.font_size = int(p.size * 2.0)
		var stack: float = p.get("stack", 0.0)
		l.position = p3(_smooth_pos, 3.6 + stack * 2.4 + (1.4 - p.t) * 1.2)


# ---------------------------------------------------------------- per-frame overlays

## Route, skid marks, request circles, beams, surge zones: all rebuilt every
## frame into one ImmediateMesh (fine for a few hundred triangles).
func _draw_fx(game) -> void:
	var im := _fx_mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	for z in game.surge_zones:
		_disc(im, p3(z.pos, 0.06), z.r / S, Color(SURGE, 0.12 + 0.08 * pulse), 40)
		_ring(im, p3(z.pos, 0.07), z.r / S, 0.25, Color(SURGE, 0.8), 48)
	_skids(im, game.car.skids)
	for sp in game.splashes:
		_splash(im, p3(sp.pos, WATER_Y + 0.05), sp.t)
	_route(im, game.route_points, Color(ROUTE, 0.9 if not game.ride.is_empty() else 0.45))
	var beam_i := 0
	for w in game.waiting:
		var c := p3(game.city.center(w.tile))
		var band: Color = BANDS[w.band]
		_disc(im, c + Vector3(0, 0.05, 0), 84.0 / S, Color(band, 0.2 + 0.12 * pulse), 28)
		_ring(im, c + Vector3(0, 0.06, 0), 84.0 / S, 0.12, band, 28)
		_beam(im, c, band, 0.45)
		_person(beam_i, c, Riders.KINDS[w.kind].color, w.surge)
		beam_i += 1
	if not game.ride.is_empty():
		var d := p3(game.city.center(game.ride.dest_tile))
		var r := 100.0 / S + 0.2 * pulse
		_disc(im, d + Vector3(0, 0.05, 0), r, Color(ROUTE, 0.18), 32)
		_ring(im, d + Vector3(0, 0.06, 0), r, 0.18, ROUTE, 32)
		_beam(im, d, ROUTE, 0.6)
	im.surface_end()
	for i in range(beam_i, _people.size()):
		_people[i].visible = false


func _tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(a)
	im.surface_set_color(col)
	im.surface_add_vertex(b)
	im.surface_set_color(col)
	im.surface_add_vertex(c)


func _disc(im: ImmediateMesh, c: Vector3, r: float, col: Color, seg: int) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		_tri(im, c, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, col)


func _ring(im: ImmediateMesh, c: Vector3, r: float, w: float, col: Color, seg: int) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_tri(im, c + d0 * r, c + d1 * r, c + d1 * (r - w), col)
		_tri(im, c + d0 * r, c + d1 * (r - w), c + d0 * (r - w), col)


## A see-through column of light, visible from blocks away.
func _beam(im: ImmediateMesh, c: Vector3, col: Color, alpha: float) -> void:
	var r := 0.9
	var h := 14.0
	var seg := 10
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var bottom := Color(col, alpha * 0.55)
		var top := Color(col, 0.0)
		im.surface_set_color(bottom)
		im.surface_add_vertex(p0)
		im.surface_set_color(bottom)
		im.surface_add_vertex(p1)
		im.surface_set_color(top)
		im.surface_add_vertex(p1 + Vector3(0, h, 0))
		im.surface_set_color(bottom)
		im.surface_add_vertex(p0)
		im.surface_set_color(top)
		im.surface_add_vertex(p1 + Vector3(0, h, 0))
		im.surface_set_color(top)
		im.surface_add_vertex(p0 + Vector3(0, h, 0))


## A splash: white rings racing outwards and droplets thrown up and falling.
func _splash(im: ImmediateMesh, c: Vector3, t: float) -> void:
	var fade := clampf(1.0 - t / 1.6, 0.0, 1.0)
	_ring(im, c, 0.6 + t * 4.5, 0.35, Color(1, 1, 1, 0.8 * fade), 32)
	_ring(im, c, 0.3 + t * 2.5, 0.25, Color(1, 1, 1, 0.6 * fade), 24)
	_disc(im, c + Vector3(0, 0.02, 0), 1.6 * fade + 0.2, Color(0.85, 0.95, 1.0, 0.7 * fade), 20)
	for i in 18:
		var a := i * 2.4
		var spd := 2.0 + float(i % 5) * 0.8
		var up := 7.0 + float(i % 3) * 2.5
		var y := up * t - 9.8 * t * t
		if y < 0.0:
			continue
		var p := c + Vector3(cos(a) * spd * t, y, sin(a) * spd * t)
		_disc(im, p, 0.22, Color(1, 1, 1, 0.9 * fade), 6)


func _route(im: ImmediateMesh, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 2:
		return
	var w := 0.18
	for i in range(1, pts.size()):
		var a := p3(pts[i - 1], 0.08)
		var b := p3(pts[i], 0.08)
		var d := (b - a)
		if d.length() < 0.001:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * w
		_tri(im, a - side, b - side, b + side, col)
		_tri(im, a - side, b + side, a + side, col)
		_disc(im, b, w, col, 8)


func _skids(im: ImmediateMesh, skids: Array) -> void:
	var col := Color(0, 0, 0, 0.35)
	for i in range(1, skids.size()):
		var a: Vector2 = skids[i - 1]
		var b: Vector2 = skids[i]
		if a == Vector2.INF or b == Vector2.INF:
			continue
		var pa := p3(a, 0.04)
		var pb := p3(b, 0.04)
		var d := pb - pa
		if d.length() < 0.001:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * 0.18
		_tri(im, pa - side, pb - side, pb + side, col)
		_tri(im, pa - side, pb + side, pa + side, col)


## A waiting passenger: a bobbing capsule in their type's colour.
func _person(i: int, c: Vector3, col: Color, surge: bool) -> void:
	while _people.size() <= i:
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.32
		cap.height = 1.3
		mi.mesh = cap
		add_child(mi)
		var head := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.24
		sph.height = 0.48
		head.mesh = sph
		head.material_override = _mat(Color("ffe0bd"))
		head.position = Vector3(0, 0.85, 0)
		mi.add_child(head)
		var tag := Label3D.new()
		tag.text = "x2"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 64
		tag.outline_size = 14
		tag.pixel_size = 0.012
		tag.modulate = SURGE
		tag.position = Vector3(0, 1.8, 0)
		tag.name = "Surge"
		mi.add_child(tag)
		_people.append(mi)
	var p: MeshInstance3D = _people[i]
	p.visible = true
	p.material_override = _mat(col)
	p.position = c + Vector3(0, 0.65 + 0.15 * absf(sin(_t * 5.0 + i)), 0)
	(p.get_node("Surge") as Label3D).visible = surge


func _arrow_mesh() -> ArrayMesh:
	# A flat arrow pointing along +X, given some thickness.
	var outline := [Vector2(1.1, 0), Vector2(0.2, -0.75), Vector2(0.2, -0.3), Vector2(-0.8, -0.3),
			Vector2(-0.8, 0.3), Vector2(0.2, 0.3), Vector2(0.2, 0.75)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(PackedVector2Array(outline))
	for y in [0.0, 0.25]:
		for i in range(0, tris.size(), 3):
			for k in 3:
				var v: Vector2 = outline[tris[i + k]]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(v.x, y, v.y))
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		for v in [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, 0.25, b.y),
				Vector3(a.x, 0, a.y), Vector3(b.x, 0.25, b.y), Vector3(a.x, 0.25, a.y)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()
