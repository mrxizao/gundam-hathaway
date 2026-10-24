# Melee hit reaction

Accepted SABER damage now starts an additive procedural visual flinch for every suit except GP03D, GP03S and Neue Ziel. It follows attack direction with backward pitch and lateral twist/roll, rises over 0.09 s, briefly holds, rebounds and returns to zero by 0.82 s. Penelope/Arizeus use reduced amplitude; nonzero forms reduce it further. Consecutive cuts restart the motion. This is a procedural whole-body reaction layered over existing animation, not a new authored skeletal clip.

Visual rotation is added to SpinPivot each effects tick. Rig-anchor calculations strip the visual rotation to retain weapon positioning. Damage, existing melee stun/slow, flight-body transform and velocity are unchanged. Hit injection occurs after friendly-fire and invulnerability guards. Mounted exterior models use a separate MeleeImpactPivot for a small shared platform response; imported transforms remain intact and the pivot is cleaned on rebuild.

Validation: all 12 profile IDs checked for accepted saber damage, exclusions, directional response/recovery, ordinary RAM damage and friendly-fire non-trigger. Mounted platform response/recovery checked. Existing first-person mounted visibility probe: 12 assertions passed. Full interactive combat animation blending and network observer rendering not tested; no new animation event replication in this change.
