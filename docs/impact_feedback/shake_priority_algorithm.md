# Embervale Camera Shake Priority and Amplitude-Capping Algorithm

## Purpose

The feedback director should make impact moments readable without allowing several simultaneous events to produce an uncontrolled camera jump. Every impact request carries a **tier**, an optional weight, a direction, and a priority. The director merges requests into one bounded camera response and separately extends hit-stop only when the requested event is stronger than the current slow-motion state.

## Feedback tiers

| Tier | Typical events | Base shake | Base hit-stop | Priority |
|---|---|---:|---:|---:|
| Light | Normal sword or projectile hit | 0.10 | 0.035 seconds | 10 |
| Medium | Enemy lunge, dash strike, combo hit | 0.18 | 0.060 seconds | 20 |
| Heavy | Hero finisher, heavy overhead, large burst | 0.32 | 0.100 seconds | 30 |
| Major | Comet landing, boss slam, phase transition | 0.52 | 0.150 seconds | 40 |
| Perfect dodge | Successful dodge through a telegraph | 0.16 | 0.050 seconds | 25 |

The values are starting targets. They should be tuned against the actual camera framing and screen size rather than treated as universal constants.

## Request normalization

For each request, clamp the input weight to `0.0..1.5`. Apply a quality multiplier after the tier is selected:

```text
qualityMultiplier = 1.0                 on desktop/full feedback
qualityMultiplier = 0.72                on mobile/full feedback
qualityMultiplier = 0.35                in reduced-motion mode
```

The requested amplitude is then:

```text
requestedAmplitude = tier.baseShake * weight * qualityMultiplier
requestedAmplitude = clamp(requestedAmplitude, 0, globalAmplitudeCap)
```

The recommended global desktop cap is `0.65` camera-local world units. The cap should apply after combining events as well as to individual requests.

## Priority merge algorithm

Maintain these state variables:

```text
activePriority
shakeEnvelope
shakeVector
shakeDecay
```

When an impact request arrives:

1. Resolve the tier profile and priority.
2. Normalize the weight and quality multiplier.
3. Calculate the bounded request amplitude.
4. Compare the request priority with `activePriority`.
5. Select a merge factor:

| Condition | Merge factor | Behavior |
|---|---:|---|
| No active shake | 1.00 | Start a new response |
| Lower priority than active | 0.25 | Add a small amount without interrupting the stronger event |
| Higher priority than active | 0.85 | Strong event takes ownership but preserves some motion |
| Equal priority | 0.55 | Combine gently to avoid machine-gun shaking |

6. Update the envelope:

```text
shakeEnvelope = min(globalAmplitudeCap,
                    shakeEnvelope + requestedAmplitude * mergeFactor)
```

7. Convert the supplied world direction into a normalized camera-local impulse. Blend 65% of the directional vector with 35% deterministic transverse jitter. Avoid purely random directions because repeatable directional feedback is easier to tune and less disorienting.
8. Add the impulse to `shakeVector` and clamp its length to `globalAmplitudeCap`.
9. Set `activePriority` to the higher priority when a stronger event arrives. Keep the current priority for equal or weaker events.
10. Apply hit-stop separately, using the longest active stop deadline rather than stacking time-scale multipliers.

## Per-frame decay

Use exponential decay so behavior is consistent across frame rates:

```text
shakeEnvelope *= exp(-shakeDecay * delta)
shakeVector = lerp(shakeVector, Vector3.ZERO,
                   1 - exp(-18 * delta))
```

Build the final offset from the directional impulse plus a small deterministic noise component:

```text
offset = shakeVector + deterministicNoise * (shakeEnvelope * 0.35)
offset = clampLength(offset, globalAmplitudeCap)
camera.position = cameraBasePosition + offset
```

Reset the priority and vectors when the envelope falls below a small threshold such as `0.005`.

## Hit-stop policy

Hit-stop is a deadline, not a stack of nested pauses:

```text
requestedUntil = now + tier.hitStopSeconds * clampedWeight
hitStopUntil = max(hitStopUntil, requestedUntil)
engineTimeScale = min(currentTimeScale, tier.hitStopTimeScale)
```

The director must remember the time scale that existed before the first hit-stop. When the deadline expires, restore that original value. This prevents a normal impact from accidentally cancelling a pre-existing cinematic slow-motion effect.

Reduced-motion mode should reduce hit-stop duration slightly but should not remove it entirely, because a short temporal accent is useful for gameplay clarity even when camera motion is disabled.

## Priority examples

### Two light hits close together

The first light hit starts the shake at `0.10`. The second uses the equal-priority factor `0.55`, producing a bounded envelope rather than two full camera jumps. The final result remains below `0.65`.

### Heavy impact followed by a light hit

The heavy event sets priority `30`. The light event has priority `10`, so it contributes only 25% of its normalized amplitude and cannot replace the heavy response.

### Light hit followed by a boss slam

The boss event has priority `40` and uses the higher-priority factor `0.85`. It takes ownership, extends hit-stop to the major tier deadline, and remains capped at the global amplitude limit.

### Perfect dodge during an enemy impact

Perfect dodge priority `25` can override a medium enemy event but cannot overwhelm a major boss event. Its chroma treatment should remain separate and cool-toned even when its camera response is merged.

## Mobile and accessibility rules

The algorithm should support the following controls:

- **Full:** use the selected platform multiplier.
- **Reduced:** use the reduced-motion multiplier and disable rotational shake first.
- **Off:** keep hit-stop and impact flash if desired, but set camera amplitude to zero.

Never allow platform multipliers or simultaneous events to bypass the global cap. Validate the cap with at least five impacts fired in the same frame.
