# Embervale Fix Queue

This folder is maintained by the **n8n Instance AI** as a structured handoff to
human developers or other AI agents. It was created on 2026-09-05 after a
runtime error audit of the `main` branch.

## What is this folder?

Each file in `fix/` describes **one specific bug** that was found during
live testing. Files follow the naming convention `FIX-<N>-<short-slug>.md`.

None of the original source files have been modified. All changes must be
applied manually or by an agent following the instructions in each fix file.

## Bug index

| File | Severity | Component | One-line summary |
|------|----------|-----------|------------------|
| [FIX-1-rig-loader-fbx.md](FIX-1-rig-loader-fbx.md) | 🔴 High | `character_rig_loader.gd` | Hero FBX ignored; loader only searches for .glb; `set_visual_root` call crashes |
| [FIX-2-target-marker-signal.md](FIX-2-target-marker-signal.md) | 🔴 High | `target_marker.gd` | `mark_locked` signal passes `Node3D`, handler expects `float` → runtime crash |
| [FIX-3-hud-skill-autotarget.md](FIX-3-hud-skill-autotarget.md) | 🟡 Medium | `hud.gd` | Mobile skill buttons skip enemy auto-select; keyboard path does it; skills appear broken on mobile |
| [FIX-4-hushling-gear-dict.md](FIX-4-hushling-gear-dict.md) | 🟡 Medium | `hushling.gd` | `result.gear` dict access at line 1436 crashes when key is absent |
| [FIX-5-hero-anim-bridge-meta.md](FIX-5-hero-anim-bridge-meta.md) | 🟡 Medium | `hero.gd` | `get_meta("anim_bridge")` called without `has_meta` guard; repeated runtime errors |
| [FIX-6-target-marker-node-cast.md](FIX-6-target-marker-node-cast.md) | 🟠 Low | `target_marker.gd` | `Node` assigned to typed `Node3D` variable without cast; watchdog timeout in tests |

## Status

- [x] FIX-1 applied — `_any_model()` resolves .glb/.fbx; `set_visual_root` path replaced by AnimTreeBridge wiring; sockets bind via Skeleton3D `BoneAttachment3D`
- [x] FIX-2 applied — slot retyped to `Node3D`; target tracking handled in `_process` (plus in-tree staleness check)
- [x] FIX-3 applied — HUD `_on_skill_pressed` auto-marks via `hero.nearest_enemy(14.0)`, the exact keyboard parity range
- [x] FIX-4 applied — loot uses `result.get("items")` / `result.get("gear")` guards
- [x] FIX-5 applied — `hero._anim_bridge()` `has_meta`-guarded helper at both call sites
- [x] FIX-6 applied — `TargetMarker` now extends `Node3D`; `tests/test_target_marker.gd` passes

## After applying fixes

Run the project's built-in audit script (if present) or open the project in
Godot 4.7 and check the Errors tab is empty. The fixes are independent — each
can be applied and tested in isolation.
