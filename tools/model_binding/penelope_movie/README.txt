Rebuild requires numpy/scipy and the original desktop source assets.
Run build_penelope_rig.py; then build_odysseus_source.py and build_odysseus_rig.py.
Use Godot --headless --path <project> --script res://tools/model_binding/penelope_movie/import_penelope_movie.gd (and import_odysseus.gd).
Legacy compatible skeleton is read from the hidden archive.
Runtime .scn files embed all resources; source GLBs are ignored by exports.
