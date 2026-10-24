# Melee shield defense and combat reaction integration

## Behavior
During an active incoming melee warning bar, a fresh successful raise_shield arms a one-use defense against that exact attacker and attack serial. This option is available throughout the bar, separately from the existing 0.2 s perfect melee parry window. It consumes the normal shield action/cooldown. On the matching saber hit, damage is rejected, the attacker saber action is stopped, a shield impact is shown, and the armed defense is consumed. Unrelated or subsequent hits use normal damage rules. It is unavailable to both mounted and carried riders; the existing shield-key dismount behavior was retained unchanged.

Unblocked saber hits retain the existing 90% slow for SLOW_TIME (4 s) and IMPACT_TIME saber recovery (3 s), but no longer lock all weapons. try_saber checks saber_locked; ranged/special weapon paths remain available through their normal cooldown/ammo gates. Existing charged cannon and Re-GZ weapon state are no longer cancelled by melee_guard.hit. No rebalance of saber damage or existing perfect parry.

## Animation integration
Confirmed hits abort active saber gameplay state and transition only an old slash/slash_* animation to the appropriate form idle with a 0.12 s blend. New firearm and shield actions can take over normally. Input trim recedes while the additive directional flinch runs; the flinch recovers to zero without physical displacement. GP03D/GP03S/Neue remain excluded from the visual reaction.

Added owner-emitted melee_hit, saber_shield and saber_shield_block visual network events. Remote receivers reproduce hit direction/animation cancellation and shield/block feedback. Damage remains owner-authoritative; no predicted remote health changes.

HUD now says saber-only restriction and separately displays the remaining 90% slow. Warning bar offers melee parry / shield defense and describes the mounted shield restriction.

## Validation
Rule probe passed for shield selection outside the perfect-parry window, one matching block, subsequent hit damage, saber-only restriction, successful vulcan firing during recovery, preserved active ranged cannon, 90% speed cap and mounted denial.

Actual Xi rig and game _slash/take_damage/effects/ModelAnimFSM chain tested: interrupted outgoing slash, successful vulcan and beam rifle firing during flinch, complete pivot recovery, shield animation entry and a second actual slash blocked with unchanged hull/I-field. GPU combat preview inspected. Twelve first-person mounted visibility assertions and twelve-profile hit-reaction regression passed earlier in this change. Main remote-fire handlers added; dual-client online play and every suit's full interactive combat were not tested.
