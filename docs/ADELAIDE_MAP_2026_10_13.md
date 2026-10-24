# Adelaide map: initial playable layout

Added ADELAIDE as a new appended map and terrain ID, registered in all/versus map lists with daytime lighting. Existing map IDs retained. Independent generation avoids changing Oenbelli and Davao.

## Scale and city
Following feedback, horizontal layout is 3x the first draft: core street plan roughly 16.2 x 18.3 km, standard buildings 27–69 m high, occasional commercial buildings 120–315 m. 2,133 buildings; unequal street intervals, small setbacks, open parcels, park ring, white festival landmark and eastern hills/woodland. Building parcels exclude roads, airport and shoreline. Geometry is batched into 30 material meshes; simplified static collision.

## Airport and sortie support
Airport reservation approximately 9.3 x 17.4 km at final game scale. Includes six open-front MS hangars, apron, runway, parallel taxiway, connectors, terminal, control tower, logistics buildings, service cranes and lane/threshold markings.

Scene path: Terrain/Adelaide/AdelaideAirport. Markers MSStand01–06 and HangarExit01–06; LaunchStart, LaunchHold, LaunchRunway, LaunchAirborne, LaunchDeparture; CameraHangar, CameraRunway, CameraDeparture. MSSortiePath is a five-point Path3D, ready for later animation wiring. Positions are already scaled, height remains in metres. This update provides the environment and anchors, not an automatically playing sortie sequence or parked live MS units.

## Loading and validation
Synchronous and staged WorldBuilder map loading both supported. Staged creation yields between land, airport, city and vegetation. Spawn radius 27 km; terrain-aware altitude clearance. Map rebuild removes the old map.

Tests: generated parcel clearance and landmark/airport/path assertions passed; WorldBuilder staged/sync/rebuild/spawn/raycast collision probe passed. GPU overview and airport previews inspected. Full AI battle, destruction, low-end hardware and menu click-through were not tested. This is a first playable procedural environment; buildings remain stylized, static and without interiors. No claim of a geographic 1:1 reconstruction.


## Building and hangar detail pass
Added building window rows, sills, side glazing, doors, cornices and three roof treatments (pitched roofs/chimneys, parapets, rooftop service equipment). Added gabled hangar roofs, repeated side buttresses, heavy portal frames, stacked sliding doors, hazard markings, clerestory glazing, bay sign strips, crane beams and maintenance cabinets. Flat normals remove diagonal smooth-shading artifacts on planar walls.

Building count remains 2,133; material batches now 43. Decoration remains batched and does not add per-window physics. Existing map integration probe passed; 18 new ray checks confirm six hangar central exit routes clear at heights 55/110/145 m. Close-range GPU building/hangar previews inspected. Full battle FPS not measured.


## Independent map/city expansion
Relative to the previous version: horizontal map dimensions x3 (area x9), city dimensions x6 (area x36). Military airport geometry, all stand/camera markers and sortie path coordinates retain their existing scale and world positions. Building heights unchanged. Spawn radius 81 km; land extent 270 km. City geometry/roads and terrain have independent scale factors. Expanded road segments are clipped outside the airport reservation, and city buildings are excluded from that same fixed world-space region. Reconnected airport access road. Terrain hill onset moved beyond city edge to keep roads/buildings grounded.

Validation: city/map scale ratios, unchanged MSStand01 position, all city roads outside military reservation, parcel clearance and integration probes passed. Final city has 2,102 buildings after exclusion; no additional building density pass in this change. Full GPU/battle performance was not measured for expanded layout.


## Post-air-raid city and material pass
Added secondary lanes, district density variation and three deterministic clustered damage zones. 1,944 parcels including 65 roofless/partially collapsed buildings. Ruins use surviving walls, exposed columns, rubble and scorched floor slabs with simplified collision. Added irregular blast basins with broken rims, ejecta edges and scattered rim stones; these sit above the existing terrain rather than excavating its collision surface.

Dedicated crater shader uses layered carbon/soil/clod/gravel noise, high roughness, low specular response and distance-faded grain. General weathering shader adds terrain patchiness, road aggregate, dirt, subtle cracks, facade soot and muted saturation. Adelaide-only time-of-day settings use dusty warm daylight, toned-down bloom and readable ambient fill. Military layout/markers remain unchanged. No new smoke particle systems.

Validation: layout/damage assertions and GPU material preview passed; map loading/rebuild, ground collision and six hangar exit clearance probes passed. Road-boundary assertion includes 0.001 local-unit float tolerance after measuring a 0.000011 local-unit edge discrepancy. Material batches 47. Full gameplay FPS and new material appearance under every rendering backend not tested.


## Torrens corridor, height and ground-aliasing correction
Reference: Australian Government Adelaide Park Lands and City Layout (https://www.dcceew.gov.au/parks-heritage/heritage/places/national/adelaide-parklands) and City of Adelaide park-land management maps. The provided aerial image depicts Port Adelaide; the central-city river is represented as a game-scale Torrens corridor separating south/core city and a lower-density northern district. Layout is an interpretation, not a geographic 1:1 replica.

Replaced a coarse terrain strip with a denser carved riverbed, separate animated teal water, bank setbacks, multiple bridge decks, piers, parapets and approach ramps. Building and tree parcels avoid the river buffer. Road segments terminate at banks; designated north/south crossings use bridges. Riverbed collision is below water. Public terrain-height query includes the carved strip. Coastline remains consistent at the west end.

Raised ordinary city heights to 240–520 m at the enlarged gameplay scale, northern district at 72% of this and selected commercial core towers 900–1,600 m. Updated window rows to span taller facades and preserved mixed roof forms. Retained clustered raid damage (61 damaged of 1,699 building parcels in this generation).

Reduced ground/noise contrast, removed crack contour pattern from general ground, added derivative-based detail suppression and distance fade to reduce pixel mosaic/shimmering. No raster bitmap textures added.

Airport construction function verified unchanged; existing sortie anchors/path retained. Tests passed for load/rebuild/spawn, original airport marker, 18 hangar corridor rays, below-water riverbed rays and bridge-deck rays; GPU river/city/material preview inspected on Compatibility renderer. Full AI battle performance and all graphics backends remain untested. Material batches: 48 plus separate water mesh.


## City model and material detail pass
Added full rear/side glazing, facade pilasters, foundation courses, narrow front sidewalk ledges, entrance canopies/steps/side posts, selected balcony slabs/rails, setback roof rooms and ventilation ducts. These decorative additions are geometry-batched and use no extra window physics nodes. Building parcels, terrain, river and airport structures retained.

Material batching now keys by color AND material class. Distinct masonry courses, concrete trim, muted glass response, roof seams, asphalt weathering and metal equipment response replace one shared rough surface. Procedural patterns use derivatives and distance fade; no new bitmap dependencies. Glass receives lower roughness and higher specular, roof equipment modest metalness. Material batches 55 for city geometry; river remains separate. Final building count 1,699 including 61 damaged parcels.

Validation: generation/parcel/damage probe passed; integration load/rebuild/spawn, riverbed/bridge collision and military corridor checks passed. GPU city overview and close facade previews inspected. Full combat FPS/low-end hardware were not measured.


## Additional urban massing and road detail
Added selected projecting bay-window towers with separated floor glazing, projecting shop awnings and setback roof volumes. Rooftop volumes receive simplified solid collision; facade/road decorations remain non-physical batch geometry. Buildings and damage counts unchanged.

Added segmented kerbs, road-edge lines, crosswalks at actual intersecting through roads, storm drains and asphalt repair patches. Kerb generation excludes intersecting-road neighborhoods, preventing segments from extending into crossings. New material classes distinguish marking paint, sidewalk/kerb paving and repair asphalt; existing asphalt receives derivative-filtered aggregate and broad mottling. Airport geometry unchanged, river bridges/routes retained.

Validation: city/parcel/damage generation and GPU facade/road previews passed. Integration map load/rebuild, river/bridge collision, spawn and military corridor checks passed before final curb-margin/window-segmentation adjustments. Geometry uses 62 material batches plus separate river mesh. No full combat/performance benchmark.


## Military airport detail pass
Added side-wall MS maintenance platforms, stairs, cabinets, work-area markings, six bay labels and overhead luminous fixtures. Added perimeter fence rails/posts with an open gap at the existing west access road, guard huts and concrete barriers beside the gate. Added a three-tank fuel yard, containment wall/pipe elements, logistics containers, static service trucks, apron floodlight structures and runway edge markers. Lighting is emissive batched geometry, not many dynamic lights. Base size, location, six stands and sortie path remain unchanged. Facilities are static set dressing without interactions or fuel explosions.

Validation: GPU hangar/base overview and city generation checks passed. Integration map rebuild, river/bridge collision, 18 hangar-center ray checks, bay label presence and four departure-path segment rays (40 m above path) passed. Final material batches 69 plus separate river and seven sign labels. No full-width animated MS collision sweep or combat FPS benchmark.
