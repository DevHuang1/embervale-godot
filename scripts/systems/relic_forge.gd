class_name RelicForge
extends Object

## === Relic Forge ===
## Turns a camera capture into a walkable 3D relic, fully offline:
## background removal -> silhouette mask -> boundary trace ->
## Ramer-Douglas-Peucker simplify -> extruded ArrayMesh with the
## capture itself as the face texture and a dark ember rim.

const TARGET_HEIGHT: float = 1.15
const EXTRUDE_DEPTH: float = 0.16
const MAX_WORK_SIZE: int = 256
const BG_TOLERANCE: float = 0.34


static func forge(source: Image) -> Dictionary:
	if source == null or source.is_empty():
		return {}
	var img := source.duplicate() as Image
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	if w > MAX_WORK_SIZE:
		var ratio := float(MAX_WORK_SIZE) / float(w)
		var new_h := maxi(int(round(img.get_height() * ratio)), 8)
		w = MAX_WORK_SIZE
		img.resize(w, new_h, Image.INTERPOLATE_BILINEAR)
	var h := img.get_height()

	# --- Background estimate from the border ring ---
	var bg := Color(0.05, 0.07, 0.05)
	var ring := maxi(2, mini(w, h) / 24)
	var bg_acc := Vector3.ZERO
	var samples := 0.0
	for y in h:
		for xx in [ring, w - 1 - ring]:
			if xx >= 0 and xx < w:
				var c := img.get_pixel(xx, y)
				bg_acc += Vector3(c.r, c.g, c.b)
				samples += 1.0
	for x in w:
		for yy in [ring, h - 1 - ring]:
			if yy >= 0 and yy < h:
				var c := img.get_pixel(x, yy)
				bg_acc += Vector3(c.r, c.g, c.b)
				samples += 1.0
	if samples > 0.0:
		bg = Color(bg_acc.x / samples, bg_acc.y / samples, bg_acc.z / samples)

	# --- Foreground mask ---
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var d := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			mask[y * w + x] = 1 if d > BG_TOLERANCE else 0
	_dilate(mask, w, h)

	# --- Keep only the largest connected blob ---
	var best_id := -1
	var best_size := 0
	var next_label := 0
	var labels := PackedInt32Array()
	labels.resize(w * h)
	labels.fill(-1)
	var stack := PackedInt32Array()
	for start in w * h:
		if mask[start] != 1 or labels[start] != -1:
			continue
		var id := next_label
		next_label += 1
		var size := 0
		stack.clear()
		stack.append(start)
		labels[start] = id
		while not stack.is_empty():
			var p: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			var px := p % w
			var py := p / w
			for nx in [px + 1, px - 1]:
				_visit(mask, labels, stack, py, w, h, id, nx)
			if py + 1 < h:
				_visit(mask, labels, stack, py + 1, w, h, id, px)
			if py - 1 >= 0:
				_visit(mask, labels, stack, py - 1, w, h, id, px)
		if size > best_size:
			best_size = size
			best_id = id
	if best_size < (w * h) / 200:
		return {}
	for p in w * h:
		mask[p] = 1 if (mask[p] == 1 and labels[p] == best_id) else 0

	# --- Boundary trace + simplify ---
	var contour := _trace_boundary(mask, w, h)
	contour = _rdp(contour, 1.6)
	if contour.size() < 8:
		return {}

	# --- Cutout texture (alpha follows the kept blob) ---
	var cutout := Image.create(w, h, false, Image.FORMAT_RGBA8)
	cutout.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				var c := img.get_pixel(x, y)
				cutout.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	var tex := ImageTexture.create_from_image(cutout)

	# --- To world space: centered, normalized height, Y flipped up ---
	var minx := contour[0].x
	var maxx := minx
	var miny := contour[0].y
	var maxy := miny
	for p in contour:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	var span_x := maxf(maxx - minx, 1.0)
	var span_y := maxf(maxy - miny, 1.0)
	var scale := TARGET_HEIGHT / maxf(span_x, span_y)
	var cx := (minx + maxx) * 0.5
	var cy := (miny + maxy) * 0.5
	var poly := PackedVector2Array()
	poly.resize(contour.size())
	for i in contour.size():
		poly[i] = Vector2(
			(contour[i].x - cx) * scale,
			-(contour[i].y - cy) * scale)

	# Normalize to counter-clockwise (positive shoelace) in world XY.
	var area := 0.0
	for i in poly.size():
		var jn := (i + 1) % poly.size()
		area += poly[i].x * poly[jn].y - poly[jn].x * poly[i].y
	if area < 0.0:
		poly.reverse()

	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return {}

	# --- Vertices: front ring, back ring (both textured), then rim quads ---
	var half := EXTRUDE_DEPTH * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var inds := PackedInt32Array()
	var out_z := Vector3(0, 0, 1)
	var down_z := Vector3(0, 0, -1)

	# Remap bounds for face UVs (world poly extents -> 0..1 over the cutout).
	var fx_min := poly[0].x
	var fx_max := fx_min
	var fy_min := poly[0].y
	var fy_max := fy_min
	for p in poly:
		fx_min = minf(fx_min, p.x)
		fx_max = maxf(fx_max, p.x)
		fy_min = minf(fy_min, p.y)
		fy_max = maxf(fy_max, p.y)

	var face_vert_start := 0
	for pi in poly.size():
		verts.append(Vector3(poly[pi].x, poly[pi].y, half))
		norms.append(out_z)
		uvs.append(_face_uv(poly[pi], fx_min, fy_min, fx_max, fy_max))
	var face_vert_mid := verts.size()
	for pi in poly.size():
		verts.append(Vector3(poly[pi].x, poly[pi].y, -half))
		norms.append(down_z)
		uvs.append(_face_uv(poly[pi], fx_min, fy_min, fx_max, fy_max))

	# Front triangles keep triangulation winding (+Z out);
	# back triangles flip it (-Z out).
	for t in idx.size() / 3:
		for k in 3:
			inds.append(idx[t * 3 + k])
		for k in 3:
			inds.append(face_vert_mid + idx[t * 3 + (2 - k)])
	var face_index_count := inds.size()
	var face_vertex_count := verts.size()

	# Rim strip: per boundary edge, two triangles wound so their cross
	# product matches the outward edge normal (dy, -dx) for CCW polys.
	var perimeter := 0.0
	for i in poly.size():
		perimeter += poly[i].distance_to(poly[(i + 1) % poly.size()])
	var acc := 0.0
	var perim_safe := maxf(perimeter, 0.001)
	for i in poly.size():
		var jn := (i + 1) % poly.size()
		var e := poly[jn] - poly[i]
		var elen := e.length()
		if elen < 0.00001:
			continue
		var outward := Vector3(e.y / elen, -e.x / elen, 0)
		var u0 := acc / perim_safe
		acc += elen
		var u1 := acc / perim_safe
		var base := verts.size()
		var fi := Vector3(poly[i].x, poly[i].y, half)
		var fj := Vector3(poly[jn].x, poly[jn].y, half)
		var bj := Vector3(poly[jn].x, poly[jn].y, -half)
		var bi := Vector3(poly[i].x, poly[i].y, -half)
		verts.append(fi); norms.append(outward); uvs.append(Vector2(u0, 1))
		verts.append(fj); norms.append(outward); uvs.append(Vector2(u1, 1))
		verts.append(bj); norms.append(outward); uvs.append(Vector2(u1, 0))
		verts.append(bi); norms.append(outward); uvs.append(Vector2(u0, 0))
		inds.append(base + 2)
		inds.append(base + 1)
		inds.append(base)
		inds.append(base + 3)
		inds.append(base + 2)
		inds.append(base)

	return _assemble(verts, norms, uvs, inds, face_index_count, face_vertex_count, tex)


static func _visit(mask: PackedByteArray, labels: PackedInt32Array,
		stack: PackedInt32Array, y: int, w: int, h: int, id: int, x: int) -> void:
	if y < 0 or y >= h or x < 0 or x >= w:
		return
	var np := y * w + x
	if mask[np] == 1 and labels[np] == -1:
		labels[np] = id
		stack.append(np)


static func _face_uv(p: Vector2, x0: float, y0: float, x1: float, y1: float) -> Vector2:
	return Vector2(
		clampf((p.x - x0) / maxf(x1 - x0, 0.001), 0.0, 1.0),
		clampf(1.0 - (p.y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0))


static func _assemble(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, inds: PackedInt32Array,
		face_index_count: int, face_vertex_count: int,
		tex: ImageTexture) -> Dictionary:
	var amesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = verts.slice(0, face_vertex_count)
	arrays[Mesh.ARRAY_NORMAL] = norms.slice(0, face_vertex_count)
	arrays[Mesh.ARRAY_TEX_UV] = uvs.slice(0, face_vertex_count)
	var fi := PackedInt32Array()
	for i in face_index_count:
		fi.append(inds[i])
	arrays[Mesh.ARRAY_INDEX] = fi
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = 0.9
	mat.specular = 0.15
	amesh.surface_set_material(0, mat)

	var rv := verts.slice(face_vertex_count, verts.size())
	var rn := norms.slice(face_vertex_count, norms.size())
	var ruv := uvs.slice(face_vertex_count, uvs.size())
	var ri := PackedInt32Array()
	for i in range(face_index_count, inds.size()):
		ri.append(inds[i] - face_vertex_count)
	if ri.size() > 0 and ri.size() % 3 == 0:
		var rarrays := []
		rarrays.resize(Mesh.ARRAY_MAX)
		rarrays[Mesh.ARRAY_VERTEX] = rv
		rarrays[Mesh.ARRAY_NORMAL] = rn
		rarrays[Mesh.ARRAY_TEX_UV] = ruv
		rarrays[Mesh.ARRAY_INDEX] = ri
		amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rarrays)
		var rim_mat := StandardMaterial3D.new()
		rim_mat.albedo_color = Color(0.14, 0.10, 0.06)
		rim_mat.roughness = 1.0
		rim_mat.emission_enabled = true
		rim_mat.emission = Color(0.35, 0.18, 0.05)
		rim_mat.emission_energy_multiplier = 0.4
		amesh.surface_set_material(1, rim_mat)

	amesh.custom_aabb = AABB(
		Vector3(-TARGET_HEIGHT, -TARGET_HEIGHT, -EXTRUDE_DEPTH),
		Vector3(TARGET_HEIGHT * 2.0, TARGET_HEIGHT * 2.0, EXTRUDE_DEPTH * 2.0))
	return {"mesh": amesh, "texture": tex}


# One dilation pass: any empty pixel touching foreground becomes foreground.
static func _dilate(mask: PackedByteArray, w: int, h: int) -> void:
	var src := mask.duplicate()
	for y in h:
		for x in w:
			var p := y * w + x
			if src[p] == 1:
				continue
			if (x > 0 and src[p - 1] == 1) \
					or (x < w - 1 and src[p + 1] == 1) \
					or (y > 0 and src[p - w] == 1) \
					or (y < h - 1 and src[p + w] == 1):
				mask[p] = 1


# Moore-neighbour boundary trace over the mask, image coords (y down).
static func _trace_boundary(mask: PackedByteArray, w: int, h: int) -> PackedVector2Array:
	var sx := -1
	var sy := 0
	for y in h:
		var found := false
		for x in w:
			if mask[y * w + x] == 1:
				sx = x
				sy = y
				found = true
				break
		if found:
			break
	if sx < 0:
		return PackedVector2Array()
	const NX := [1, 1, 0, -1, -1, -1, 0, 1]
	const NY := [0, 1, 1, 1, 0, -1, -1, -1]
	var px := sx
	var py := sy
	var bdir := 4
	var pts := PackedVector2Array()
	var guard := w * h * 4
	while guard > 0:
		guard -= 1
		pts.append(Vector2(px, py))
		var stepped := false
		for k in 8:
			var d := (bdir + 1 + k) % 8
			var nx: int = px + NX[d]
			var ny: int = py + NY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if mask[ny * w + nx] == 1:
				bdir = (d + 4) % 8
				px = nx
				py = ny
				stepped = true
				break
		if not stepped:
			break
		if px == sx and py == sy:
			break
	return pts


# Ramer-Douglas-Peucker polyline simplification.
static func _rdp(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var ranges: Array = [[0, points.size() - 1]]
	while not ranges.is_empty():
		var r: Array = ranges.pop_back()
		var a: int = r[0]
		var b: int = r[1]
		var dmax := -1.0
		var imax := -1
		for i in range(a + 1, b):
			var d := _point_line_dist(points[i], points[a], points[b])
			if d > dmax:
				dmax = d
				imax = i
		if dmax > epsilon and imax > 0:
			keep[imax] = 1
			ranges.append([a, imax])
			ranges.append([imax, b])
	var out := PackedVector2Array()
	for i in points.size():
		if keep[i] == 1:
			out.append(points[i])
	return out


static func _point_line_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# === Dominant-color extraction (boss customization palettes) ===
## Coarse RGB bucket vote over the foreground of a capture, weighted by
## saturation so washed-out background pixels lose to vivid subject colors.
static func extract_palette(source: Image, count: int = 3) -> Array[Color]:
	var out: Array[Color] = []
	if source == null or source.is_empty():
		return out
	var img := source.duplicate() as Image
	img.convert(Image.FORMAT_RGB8)
	img.resize(48, 48, Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var sums := {}   # bucket key -> [r, g, b, weight]
	var ring := maxi(2, mini(w, h) / 8)
	for y in range(ring, h - ring):
		for x in range(ring, w - ring):
			var c := img.get_pixel(x, y)
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			var sat := mx - mn
			var weight := sat * sat + 0.02  # vivid pixels dominate the vote
			var key := Vector3i(int(c.r * 7.0), int(c.g * 7.0), int(c.b * 7.0))
			if not sums.has(key):
				sums[key] = [0.0, 0.0, 0.0, 0.0]
			var acc: Array = sums[key]
			acc[0] += c.r * weight
			acc[1] += c.g * weight
			acc[2] += c.b * weight
			acc[3] += weight
	if sums.is_empty():
		return out
	var ranked := sums.keys()
	ranked.sort_custom(func(a, b):
		return float(sums[a][3]) > float(sums[b][3]))
	for i in mini(count, ranked.size()):
		var acc: Array = sums[ranked[i]]
		var tw := maxf(float(acc[3]), 0.0001)
		out.append(Color(clampf(acc[0] / tw, 0, 1),
			clampf(acc[1] / tw, 0, 1), clampf(acc[2] / tw, 0, 1)))
	# Pad with grove-flavored defaults so palettes stay usable
	var fallbacks := [Color(0.55, 0.30, 0.16), Color(0.96, 0.72, 0.29),
		Color(0.30, 0.42, 0.30)]
	while out.size() < count:
		out.append(fallbacks[out.size() % fallbacks.size()])
	return out