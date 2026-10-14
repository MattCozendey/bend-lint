import Base
import ./dda.bend as X
import ./voxel.bend as V
import ./material.bend as M
import ./lighting.bend as L
import ./render.bend as R

law material_foundation_id:
	{M.Material.id(M.Foundation{}) == 1 : U32}

law material_concrete_id:
	{M.Material.id(M.Concrete{}) == 2 : U32}

law material_frame_id:
	{M.Material.id(M.Frame{}) == 3 : U32}

law material_machinery_id:
	{M.Material.id(M.Machinery{}) == 4 : U32}

law material_read_id:
	for +material: M.Material
	{M.Material.read(M.Material.id(material)) == Some{material} : Maybe<&2, M.Material>}

law material_id_nonzero:
	for material: M.Material
	{U32.is_ne(M.Material.id(material), 0) == True{} : Bool}

law material_palette_lookup:
	for +palette: M.Palette
	for +material: M.Material
	for +light: M.Light
	{M.Palette.surface(palette, M.Material.id(material), light) == M.Palette.color(palette, material, light) : U32}

law erase_idempotent:
	for material: U32
	for hit: Bool
	{V.Cell.erase(V.Cell.erase(material, hit), hit) == V.Cell.erase(material, hit) : U32}

law erase_miss_preserves_material:
	for material: U32
	{V.Cell.erase(material, False{}) == material : U32}

law erase_hit_removes_material:
	for material: U32
	{V.Cell.erase(material, True{}) == 0 : U32}

law occupied_neighbor_hides_face:
	for solid: Bool
	{V.Face.exposed(solid, True{}) == False{} : Bool}

law empty_cell_has_no_face:
	for neighbor: Bool
	{V.Face.exposed(False{}, neighbor) == False{} : Bool}

law isolated_solid_has_face:
	{V.Face.exposed(True{}, False{}) == True{} : Bool}


law daylight_palette_lookup:
	for +palette: L.Palette
	for +material: M.Material
	for +direction: V.Direction
	{L.Palette.surface(palette, M.Material.id(material), direction) == L.Palette.color(palette, material, direction) : L.Ramp}

law unlit_color_preserved:
	for +color: U32
	for visible: U32
	{L.Ramp.color(L.Ramp.constant(color), visible) == color : U32}

law occluded_sun_sample:
	{L.Shadow.visible(True{}) == 0 : U32}

law clear_sun_sample:
	{L.Shadow.visible(False{}) == 1 : U32}

law material_plaster_id:
	{M.Material.id(M.Plaster{}) == 5 : U32}

law unit_face_projection_matches_rectangle:
	for +cell: V.Cell
	for +direction: V.Direction
	for +material: U32
	for +basis: R.Basis
	for +palette: L.Palette
	for +id: U32
	{R.Projected.of(V.Face{cell, direction, material}, basis, palette, id) == R.Projected.of(V.Rectangle{cell, direction, material, 1, 1}, basis, palette, id) : Maybe<&2, R.Projected>}

law illuminated_unit_face_projection_matches_rectangle:
	for +cell: V.Cell
	for +direction: V.Direction
	for +material: U32
	for +basis: R.Basis
	for +palette: L.Palette
	for +id: U32
	for +visibility: L.ColorField
	{R.Projected.illuminated(R.Illuminated{V.Face{cell, direction, material}, visibility}, basis, palette, id) == R.Projected.illuminated(R.Illuminated{V.Rectangle{cell, direction, material, 1, 1}, visibility}, basis, palette, id) : Maybe<&2, R.Projected>}

law pending_existing_preserved:
	for +hit: R.Hit
	{R.PendingHit.finish(R.Existing{hit}) == hit : R.Hit}

law pending_accept_preserves_hit:
	for +closer: Bool
	for +cell: V.Cell
	for +depth: F32
	for +color: L.Ramp
	for +visibility: L.ColorField
	for +u: F32
	for +v: F32
	for +edge: Bool
	for +id: U32
	for +direction: V.Direction
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.accept(closer, cell, depth, color, visibility, u, v, edge, id, direction, old)) == R.Hit.accept(closer, cell, depth, color, visibility, u, v, edge, id, direction, R.PendingHit.finish(old)) : R.Hit}

law pending_covered_preserves_hit:
	for +covered: Bool
	for +u: F32
	for +v: F32
	for +cell: V.Cell
	for +depth: F32
	for +color: L.Ramp
	for +visibility: L.ColorField
	for +id: U32
	for +direction: V.Direction
	for +outline: Bool
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.covered(covered, u, v, cell, depth, color, visibility, id, direction, outline, old)) == R.Hit.covered(covered, u, v, cell, depth, color, visibility, id, direction, outline, R.PendingHit.finish(old)) : R.Hit}

law pending_intersection_preserves_hit:
	for +nonparallel: Bool
	for +denom: F32
	for +plane: F32
	for +u_eye: F32
	for +v_eye: F32
	for +du: F32
	for +dv: F32
	for +near: F32
	for +cell: V.Cell
	for +color: L.Ramp
	for +visibility: L.ColorField
	for +id: U32
	for +direction: V.Direction
	for +width: F32
	for +height: F32
	for +outline: Bool
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.intersection(nonparallel, denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, old)) == R.Hit.intersection(nonparallel, denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, R.PendingHit.finish(old)) : R.Hit}

law pending_axes_preserves_hit:
	for +face: R.Projected
	for +axis: R.Vec3
	for +near: F32
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.axes(face, axis, near, old)) == R.Hit.axes(face, axis, near, R.PendingHit.finish(old)) : R.Hit}

law pending_face_preserves_hit:
	for +face: R.Projected
	for +ray: R.Vec3
	for +near: F32
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.face(face, ray, near, old)) == R.Hit.face(face, ray, near, R.PendingHit.finish(old)) : R.Hit}

law pending_scan_preserves_hit:
	for +faces: List<&2, R.Projected>
	for +ray: R.Vec3
	for +near: F32
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.scan(faces, ray, near, old)) == R.Pixel.eager(faces, ray, near, R.PendingHit.finish(old)) : R.Hit}

law final_lighting_preserves_hit:
	for +faces: List<&2, R.Projected>
	for +ray: R.Vec3
	for +near: F32
	for +hit: R.Hit
	{R.Pixel.hit(faces, ray, near, hit) == R.Pixel.eager(faces, ray, near, hit) : R.Hit}

law dda_uniform_material:
	for +material: U32
	for axis: X.Split
	for leftward: Bool
	for cell: V.Cell
	for span: V.Cell
	{X.Tree.read(X.Solid{material},axis,leftward,cell,span) == material : U32}

law dda_cached_daylight_preserved:
	for +sides: L.Sides
	for +direction: V.Direction
	{X.Sides.color(X.Sides.cached(sides),direction) == L.Ramp.color(L.Sides.surface(sides,direction),9) : U32}

law dda_outside_is_empty:
	for cells: X.Tree
	for side: U32
	for cell: V.Cell
	{X.Grid.read.valid(False{},cells,side,cell) == 0 : U32}

law dda_disjoint_paint_preserves_grid:
	for fuel: Nat
	for covers: Bool
	for box: V.Cuboid
	for region: V.Cuboid
	for axis: U32
	for +tree: X.Tree
	{X.Tree.paint(fuel,False{},covers,box,region,axis,tree) == tree : X.Tree}

law dda_face_flip_involution:
	for +direction: V.Direction
	{X.Direction.flip(X.Direction.flip(direction)) == direction : V.Direction}

law dda_stationary_axis_never_crosses:
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	{X.Axis.next(False{},positive,origin,delta,cell) == 1.0e30 : F32}

law dda_uncrossed_coordinate_preserved:
	for positive: Bool
	for +cell: U32
	{X.Axis.step(False{},positive,cell) == cell : U32}

law dda_traversal_is_bounded:
	for inside: Bool
	for material: U32
	for previous: U32
	for grid: X.Grid
	for eye: R.Vec3
	for ray: R.Vec3
	for crossing: X.Crossing
	{X.Trace.walk(0n,inside,material,previous,grid,eye,ray,crossing) == None{} : Maybe<&2,X.SurfaceHit>}

law dda_region_material_preserved:
	for +tree: X.Tree
	for +axis: X.Split
	for +leftward: Bool
	for +cell: V.Cell
	for +span: V.Cell
	for low: V.Cell
	{X.Region.material(X.Tree.region(tree,axis,leftward,cell,span,low)) == X.Tree.read(tree,axis,leftward,cell,span) : U32}

law dda_region_outside_is_empty:
	for cells: X.Tree
	for side: U32
	for cell: V.Cell
	{X.Region.material(X.Grid.region.valid(False{},cells,side,cell)) == 0 : U32}

law dda_stationary_region_axis_preserved:
	for positive: Bool
	for origin: F32
	for delta: F32
	for +cell: U32
	for time: F32
	for low: U32
	for high: U32
	{X.Axis.advance(False{},positive,origin,delta,cell,time,low,high) == X.Advance{cell,cell,False{}} : X.Advance}

law dda_region_traversal_is_bounded:
	for inside: Bool
	for previous: U32
	for grid: X.Grid
	for eye: R.Vec3
	for ray: R.Vec3
	for crossing: X.Crossing
	for region: X.Region
	{X.Trace.regions(0n,inside,previous,grid,eye,ray,crossing,region) == None{} : Maybe<&2,X.SurfaceHit>}

law dda_zero_plane_events_are_accepted:
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	{X.Axis.before(positive,origin,delta,cell,time,0) == True{} : Bool}

law dda_count_down_stops_at_accepted_plane:
	for fuel: Nat
	for at_limit: Bool
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +count: U32
	for limit: U32
	{X.Axis.correct(1n+fuel,False{},True{},at_limit,positive,origin,delta,cell,time,count,limit) == count : U32}

law dda_count_up_rejects_first_late_plane:
	for fuel: Nat
	for at_limit: Bool
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +count: U32
	for limit: U32
	{X.Axis.correct(1n+fuel,True{},False{},at_limit,positive,origin,delta,cell,time,count,limit) == (count - 1 : U32) : U32}

law dda_count_up_stops_at_accepted_limit:
	for fuel: Nat
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +limit: U32
	{X.Axis.correct(1n+fuel,True{},True{},True{},positive,origin,delta,cell,time,limit,limit) == limit : U32}
