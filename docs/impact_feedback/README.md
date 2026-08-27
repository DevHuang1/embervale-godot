# Embervale Impact Feedback Deliverables

This directory contains a C# reference implementation and an algorithm specification for the next camera-feedback polish pass.

## Files

- `ImpactDirector.cs` — Godot C# reference implementation with `Light`, `Medium`, `Heavy`, `Major`, and `PerfectDodge` feedback tiers.
- `shake_priority_algorithm.md` — detailed priority merge, exponential decay, hit-stop deadline, mobile cap, and reduced-motion behavior.
- `../../scripts/systems/impact_director.gd` — native integrated tier definitions and feedback dispatcher.
- `../../scripts/systems/camera_rig.gd` — native priority-aware shake, amplitude cap, hit-stop, and feedback-mode implementation.
- `../../tests/impact_feedback_validation.gd` — executable Grove/Moonfen behavior matrix.
- `../../tests/impact_feedback_benchmark.gd` — automated multi-actor frame-time and dispatch benchmark.

## Integration note

The current project now uses the native GDScript implementation. Existing `ImpactDirector.apply_strike()` calls route into `CameraRig.request_feedback()`, while retaining the existing CombatFx, audio, debris, and elemental payload systems. The C# file remains as a typed reference for a future C# branch or port.

The benchmark intentionally measures the feedback core directly through `CameraRig.request_feedback()` to isolate shake merging and hit-stop bookkeeping from pooled VFX/audio allocation costs. The separate behavior harness exercises the current GDScript ImpactDirector downstream VFX/audio path.

## Running the validation harness

From the Embervale project root, run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --path . \
  --scene res://tests/impact_feedback_validation.tscn
```

A successful run ends with:

```text
RESULT: PASS
```

The test exits with status `0` on success and status `1` when one or more assertions fail.

## Running the performance benchmark

Run the benchmark with:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \\
  --headless \\
  --path . \\
  --scene res://tests/impact_feedback_benchmark.tscn
```

The benchmark tests `1, 4, 8, 16, 32, and 64` simultaneous requests for `medium`, `heavy`, and `major` tiers in both Grove and Moonfen. It reports dispatch p95/max, frame p95/max, spike count against a dynamic threshold, peak amplitude, cap status, and observed time scale. A JSON report is written to `user://impact_feedback_benchmark.json`.

## Manual validation

Run Grove and Moonfen in the Godot editor with **F6**. Observe normal attacks, heavy attacks, dash strikes, Comet, enemy lunges, perfect dodges, and the Matriarch slam. Verify that stronger events feel stronger but that multiple simultaneous impacts never move the camera outside the configured cap. Repeat with the future reduced-motion/mobile setting enabled.
