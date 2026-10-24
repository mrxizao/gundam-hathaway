# First-person mounted model and exhaust visibility

Root cause: Gustav single platform scene assets/models/gustav_single/mounted.scn includes rider geometry outside FlightBody.model_root. First-person previously hid only the rider model. Thruster particles, nozzle glows and boost trails also live outside that subtree.

FlightBody.set_model_visible now syncs the ridden board even when the visibility wish has not changed. FlightPedal hides its imported exterior and PedalPropulsion subtree in ridden cockpit view; visibility is reapplied after model/propulsion rebuild. Detached/inbound platforms restore their exterior. Physics, rigs, muzzle anchors and propulsion simulation remain active.

FlightBody hides single/multi-nozzle exhaust, boost/dash particles and boost trail rendering in cockpit view. Glow suppression runs after effects updates so emissions cannot turn it back on. Third-person restores exterior/effects. Independent AI boards are not hidden through global settings.

Validation: 12 assertions using the actual Gustav single mounted asset passed, including cockpit hide, unchanged-wish mounting, emitter/glow suppression, third-person restore, detached board and independent AI board. Flare capacity probe: 6 assertions passed before concurrent melee changes. Concurrent melee-system edits were retained and the 12 visibility assertions rerun successfully after merging. Full interactive cockpit transition/visual flight not tested.
