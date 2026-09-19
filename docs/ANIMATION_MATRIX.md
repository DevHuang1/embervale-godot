# Embervale animation matrix

This is the production coverage sheet for the current Godot 4 character
animation contract. `EntityAnimator` remains the deterministic fallback;
`CharacterRigLoader` may replace it with an authored rig only when the asset
and clip are present. Missing authored clips must never remove gameplay cues.

| Actor / role | Idle | Move | Turn | Attack / cast | Hit / stagger | Death | Interact / special | Current source |
|---|---|---|---|---|---|---|---|---|
| Hero | fallback | fallback | fallback | procedural weapon timing | fallback | fallback | socket/equipment cues | `EntityAnimator` + authored hero rig when available |
| Hushling / sprite | fallback | fallback | fallback | procedural attack variants | fallback | fallback | variant-specific cues | `EntityAnimator` |
| Ranged / spore roles | fallback | fallback | fallback | telegraph + cast timing | fallback | fallback | cloud/volley cues | `Hushling` + `EntityAnimator` |
| Humanoid NPC | fallback | fallback | fallback | not required in current slice | fallback | not required | interaction prompt | authored Kenney FBX or procedural fallback |
| Biome boss | fallback | fallback | fallback | phase-specific telegraphed attacks | crown/phase reaction | tumble/ragdoll fallback | phase evolution / intro | `BossBase` + authored boss variant |
| Training target | idle/reset | none | none | none | reset | none | practice label | `CombatTrainingTarget` |

## Clip contract before a rig is marked production-ready

- Every authored rig must expose a stable idle and locomotion path.
- Attack or cast clips must align their impact marker with the shared damage
  event; the authored clip may change presentation, never collision timing.
- Hit, stagger, and death must have a procedural fallback and a cleanup path.
- Special/phase clips are optional; the gameplay signal and telegraph remain
  authoritative when a clip is missing.
- Weapon sockets must be checked at normal scale and at the Android camera
  distance before visual approval.

## Evidence to collect

1. Run `tests/test_imported_character_models.gd` for asset mount coverage.
2. Run boss phase and encounter contract validations for timing coverage.
3. Capture a real-render hero, humanoid, enemy, and boss pass before checking
   off visual alignment.
