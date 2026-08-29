#!/usr/bin/env bash
# Visual pass validation runner.
# Runs every relevant headless suite and treats ANY SCRIPT ERROR in the
# output as a hard failure, so a runtime exception can no longer hide
# behind an "ALL TESTS PASSED" summary line.
#
# Usage:  bash scripts/checks/run_visual_suites.sh
set -u

cd "$(dirname "$0")/../.." || exit 2
GODOT="${GODOT:-godot}"

# Scene-based Node harnesses (autoloads initialize through their .tscn).
SCENE_SUITES=(
  "res://tests/impact_feedback_validation.tscn"
  "res://tests/realm_expansion_validation.tscn"
  "res://tests/elemental_status_validation.tscn"
  "res://tests/boss_phase_transition_validation.tscn"
)

# SceneTree headless suites.
SCRIPT_SUITES=(
  "tests/test_material_bindings.gd"
  "tests/test_quality_scaler.gd"
  "tests/test_visual_vfx_budgets.gd"
  "tests/test_vfx_ui_smoke.gd"
  "tests/test_realm_visuals.gd"
  "tests/test_biomes.gd"
)

overall_fail=0
error_msgs=()

# Per-suite wall-clock cap: a hung suite fails fast instead of stalling the
# whole batch. Full-world suites get headroom; a stuck process is killed.
SUITE_TIMEOUT="${SUITE_TIMEOUT:-180}"

run_one() {
  local label="$1"
  local spec="$2"
  local kind="$3"
  local out_file
  out_file="$(mktemp)"
  if [ "$kind" = "script" ]; then
    "$GODOT" --headless --path . --script "$spec" >"$out_file" 2>&1 &
  else
    "$GODOT" --headless --path . "$spec" >"$out_file" 2>&1 &
  fi
  local pid=$!
  ( sleep "$SUITE_TIMEOUT"; kill -9 "$pid" 2>/dev/null ) &
  local killer=$!
  local status=0
  wait "$pid" || status=$?
  kill "$killer" 2>/dev/null
  local out
  out="$(cat "$out_file")"
  rm -f "$out_file"
  echo "=== $label ==="
  echo "$out" | tail -3
  if echo "$out" | grep -q "SCRIPT ERROR"; then
    echo "FAIL($label): SCRIPT ERROR detected"
    error_msgs+=("$label: SCRIPT ERROR")
    overall_fail=1
  elif [ "$status" -ne 0 ]; then
    echo "FAIL($label): exit status $status"
    error_msgs+=("$label: exit $status")
    overall_fail=1
  else
    echo "PASS($label)"
  fi
}

for suite in "${SCENE_SUITES[@]}"; do
  run_one "$suite" "$suite" "scene"
done

for suite in "${SCRIPT_SUITES[@]}"; do
  run_one "$suite" "$suite" "script"
done

if [ "$overall_fail" -ne 0 ]; then
  echo "=== VISUAL SUITES: FAIL ==="
  for msg in "${error_msgs[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
echo "=== VISUAL SUITES: ALL PASS ==="
exit 0