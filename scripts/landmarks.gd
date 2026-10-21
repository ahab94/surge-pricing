extends RefCounted
## Landmark models, built from simple shapes in code. Each city places some
## (cities.gd "landmarks"); view3d.gd calls build() for each one.
##
## They are generic, recognisable silhouettes ("an iron lattice tower", "an
## ancient arena"), not replicas of any particular building's design.
##
## Units: 1 tile = 4 units. A landmark is built around its footprint's centre,
## standing on the ground (y = 0). `w` and `h` are the footprint in tiles.

const INK := Color("2a2d36")

var _mats := {}


func _mat(col: Color, emission := false) -> StandardMaterial3D:
	var key := col.to_html() + ("e" if emission else "")
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.75
		if emission:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 1.4
		_mats[key] = m
	return _mats[key]


func _box(root: Node3D, size: Vector3, pos: Vector3, col: Color, emission := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(col, emission)
	root.add_child(mi)
	return mi


## A frustum (or cylinder, or cone with top = 0). sides = 4 gives a square one.
func _cyl(root: Node3D, bottom: float, top: float, height: float, pos: Vector3, col: Color,
		sides := 16, emission := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.position = pos + Vector3(0, height * 0.5, 0)
	mi.material_override = _mat(col, emission)
	if sides == 4:
		mi.rotation.y = PI / 4.0   # square, edges lined up with the streets
	root.add_child(mi)
	return mi


## A straight beam between two points (lattice members, legs, cables).
func _beam(root: Node3D, a: Vector3, b: Vector3, thick: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(thick, len, thick)
	mi.mesh = bm
	mi.material_override = _mat(col)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	root.add_child(mi)


func build(lm: Dictionary, night := false) -> Node3D:
	var root := Node3D.new()
	var fw := float(lm.w) * 4.0
	var fd := float(lm.h) * 4.0
	match String(lm.kind):
		"iron_tower":
			_lattice(root, fw, [Color("6b4f3a")], 22.0)
		"red_tower":
			_lattice(root, fw, [Color("e2402c"), Color("f4f4f4")], 20.0)
		"arch":
			var stone := Color("bfb092")
			_box(root, Vector3(fw * 0.3, 6.0, fd * 0.5), Vector3(-fw * 0.32, 3.0, 0), stone)
			_box(root, Vector3(fw * 0.3, 6.0, fd * 0.5), Vector3(fw * 0.32, 3.0, 0), stone)
			_box(root, Vector3(fw * 0.95, 2.2, fd * 0.55), Vector3(0, 7.1, 0), stone)
			_box(root, Vector3(fw, 0.4, fd * 0.6), Vector3(0, 8.4, 0), stone.darkened(0.15))
		"statue":
			var stone := Color("9c917e")
			var green := Color("6fbfa6")
			_box(root, Vector3(fw * 0.55, 3.0, fd * 0.55), Vector3(0, 1.5, 0), stone)
			_cyl(root, fw * 0.24, fw * 0.2, 2.0, Vector3(0, 3.0, 0), stone.lightened(0.1), 8)
			_cyl(root, 1.1, 0.55, 5.0, Vector3(0, 5.0, 0), green, 10)          # robe
			_cyl(root, 0.45, 0.45, 0.9, Vector3(0, 10.0, 0), green, 10)        # head
			for i in 7:                                                        # crown spikes
				var a := -PI * 0.5 + (i - 3) * 0.32
				_beam(root, Vector3(0, 10.8, 0), Vector3(cos(a) * 0.9, 11.4, sin(a) * 0.9), 0.12, green)
			_beam(root, Vector3(0.5, 8.6, 0), Vector3(0.7, 12.2, 0), 0.35, green)   # raised arm
			_cyl(root, 0.35, 0.0, 0.8, Vector3(0.72, 12.2, 0), Color("ffc93c"), 8, true)  # torch flame
			_box(root, Vector3(0.6, 0.15, 0.9), Vector3(-0.9, 8.2, 0.2), green)    # tablet
		"spire":
			var glass := Color("8fa9bd")
			var tiers := [[fw * 0.3, 5.0], [fw * 0.24, 4.5], [fw * 0.18, 4.0], [fw * 0.12, 3.5], [fw * 0.07, 3.0]]
			var y := 0.0
			for tier in tiers:
				_cyl(root, tier[0], tier[0] * 0.9, tier[1], Vector3(0, y, 0), glass, 6)
				y += tier[1]
			_cyl(root, 0.25, 0.02, 5.0, Vector3(0, y, 0), Color("d9e2ea"), 6)
		"deco_tower":
			var stone := Color("b3a68f")
			var y := 0.0
			for tier in [[0.8, 8.0], [0.6, 4.5], [0.42, 3.0], [0.28, 2.0]]:
				_box(root, Vector3(fw * tier[0], tier[1], fd * tier[0]), Vector3(0, y + tier[1] * 0.5, 0), stone)
				y += tier[1]
			_cyl(root, 0.4, 0.05, 6.0, Vector3(0, y, 0), Color("c0c8cf"), 8)
		"arena":
			_arena(root, fw, fd)
		"clock_tower":
			var stone := Color("b89a5e")
			_box(root, Vector3(fw * 0.5, 13.0, fd * 0.5), Vector3(0, 6.5, 0), stone)
			_box(root, Vector3(fw * 0.6, 3.0, fd * 0.6), Vector3(0, 14.5, 0), stone.lightened(0.1))
			for d in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				var face := _cyl(root, 1.0, 1.0, 0.12, Vector3.ZERO, Color("fbf6e6"), 20)
				face.rotation = Vector3(PI / 2.0, 0, 0) if absf(d.z) > 0.5 else Vector3(0, 0, PI / 2.0)
				face.position = Vector3(0, 14.5, 0) + d * (fw * 0.3 + 0.07)
				_box(root, Vector3(0.12, 0.8, 0.12), Vector3(0, 14.8, 0) + d * (fw * 0.3 + 0.2), INK)
			_cyl(root, fw * 0.36, 0.0, 6.0, Vector3(0, 16.0, 0), Color("4f6b5a"), 4)
		"wheel":
			_wheel(root, fd)
		"round_tower":
			var stone := Color("a8957a")
			_cyl(root, fw * 0.32, fw * 0.3, 12.0, Vector3.ZERO, stone, 16)
			_cyl(root, fw * 0.35, fw * 0.35, 0.6, Vector3(0, 10.0, 0), stone.darkened(0.2), 16)
			_cyl(root, fw * 0.34, 0.0, 5.0, Vector3(0, 12.0, 0), Color("5d6e7a"), 16)
		"supertrees":
			var n := int(lm.get("count", 5))
			for i in n:
				var a := i * TAU / n + 0.3
				var p := Vector3(cos(a) * fw * 0.3, 0, sin(a) * fd * 0.3) if i > 0 else Vector3.ZERO
				var hgt := 5.0 + float((i * 37) % 4)
				_cyl(root, 0.35, 0.22, hgt, p, Color("6f5a7a"), 8)
				var top := Color("9fd36b") if i % 2 == 0 else Color("d36bc4")
				_cyl(root, 0.25, 1.5, 1.2, p + Vector3(0, hgt, 0), top, 12, night)
		"jagged_tower":
			var glass := Color("9fb3c4")
			var y := 0.0
			for i in 12:
				var s := 1.0 - i * 0.03
				var bite := 0.25 if i % 3 == 1 else 0.0
				_box(root, Vector3(fw * 0.55 * s - bite * 3.0, 2.5, fd * 0.55 * s), Vector3(bite * 1.5, y + 1.25, 0), glass)
				y += 2.5
		"pylons":
			# A pair of suspension-bridge towers with cables (stands in water).
			for side in [-1.0, 1.0]:
				var base := Vector3(0, 0, side * fd * 0.5)
				_box(root, Vector3(0.6, 14.0, 0.6), base + Vector3(-1.6, 7.0, 0), Color("c9ced6"))
				_box(root, Vector3(0.6, 14.0, 0.6), base + Vector3(1.6, 7.0, 0), Color("c9ced6"))
				_box(root, Vector3(3.8, 0.6, 0.6), base + Vector3(0, 13.0, 0), Color("c9ced6"))
			for x in [-1.6, 1.6]:
				_beam(root, Vector3(x, 13.5, -fd * 0.5), Vector3(x, 1.2, 0), 0.08, INK)
				_beam(root, Vector3(x, 13.5, fd * 0.5), Vector3(x, 1.2, 0), 0.08, INK)
		"umbrellas":
			var cols := [Color("ff6b6b"), Color("ffd23f"), Color("4dabf7"), Color("69db7c")]
			for i in 6:
				var p := Vector3((i % 3 - 1) * fw * 0.3, 0, (i / 3 - 0.5) * fd * 0.5)
				_box(root, Vector3(0.08, 1.6, 0.08), p + Vector3(0, 0.8, 0), Color("eeeeee"))
				_cyl(root, 1.0, 0.05, 0.5, p + Vector3(0, 1.5, 0), cols[i % cols.size()], 8)
		_:
			_box(root, Vector3(fw * 0.8, 4.0, fd * 0.8), Vector3(0, 2.0, 0), Color("cccccc"))
	return root


## A tapering lattice tower (four legs that arch in, platforms, a spire).
## `bands` alternates colours by section (red and white for one city).
func _lattice(root: Node3D, size: float, bands: Array, height: float) -> void:
	var levels := [[0.0, size * 0.42], [height * 0.25, size * 0.22], [height * 0.5, size * 0.12],
			[height * 0.85, size * 0.05], [height, size * 0.02]]
	for i in levels.size() - 1:
		var y0: float = levels[i][0]
		var w0: float = levels[i][1]
		var y1: float = levels[i + 1][0]
		var w1: float = levels[i + 1][1]
		var col: Color = bands[i % bands.size()]
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_beam(root, Vector3(sx * w0, y0, sz * w0), Vector3(sx * w1, y1, sz * w1), 0.5 if i == 0 else 0.35, col)
		# Cross bracing on each face.
		for k in 4:
			var a := Vector3(w0, y0, w0).rotated(Vector3.UP, k * PI / 2.0)
			var b := Vector3(-w1, y1, w1).rotated(Vector3.UP, k * PI / 2.0)
			_beam(root, a, b, 0.14, col.darkened(0.15))
		if i < 2:   # platforms
			_box(root, Vector3(w1 * 2.4, 0.5, w1 * 2.4), Vector3(0, y1, 0), col.darkened(0.2))
	_cyl(root, 0.18, 0.02, 3.0, Vector3(0, height, 0), bands[0], 6)


## An oval of stacked arches; one side crumbled lower.
func _arena(root: Node3D, fw: float, fd: float) -> void:
	var stone := Color("d9b47a")
	var n := 28
	for i in n:
		var a := i * TAU / n
		var p := Vector3(cos(a) * fw * 0.42, 0, sin(a) * fd * 0.42)
		var hgt := 5.5 if sin(a) < 0.3 else 3.5
		var seg := _box(root, Vector3(1.9, hgt, 0.9), p + Vector3(0, hgt * 0.5, 0), stone)
		seg.rotation.y = -a + PI / 2.0
		for row in int(hgt / 1.8):   # arch openings: dark recesses on the outside
			var o := _box(root, Vector3(0.7, 1.0, 0.1), p * 1.03 + Vector3(0, 0.9 + row * 1.8, 0), Color("6b5236"))
			o.rotation.y = -a + PI / 2.0
	_cyl(root, fw * 0.3, fw * 0.3, 0.3, Vector3.ZERO, Color("c2a46e"), 24)   # the arena floor


## An observation wheel on an A-frame, facing the camera's side.
func _wheel(root: Node3D, size: float) -> void:
	var r := size * 0.45
	var hub := Vector3(0, r + 1.0, 0)
	var white := Color("f2f4f7")
	var n := 20
	for i in n:
		var a0 := i * TAU / n
		var a1 := (i + 1) * TAU / n
		var p0 := hub + Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := hub + Vector3(cos(a1) * r, sin(a1) * r, 0)
		_beam(root, p0, p1, 0.25, white)
		if i % 2 == 0:
			_beam(root, hub, p0, 0.08, white)
			_box(root, Vector3(0.7, 0.6, 0.7), p0 + Vector3(0, -0.4, 0), Color("9fd3f0"))
	_beam(root, Vector3(-r * 0.6, 0, 0.6), hub, 0.4, white)
	_beam(root, Vector3(r * 0.6, 0, 0.6), hub, 0.4, white)
