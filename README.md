# Embervale

A stylized dark-fantasy action RPG built in **Godot 4.7**, Android-first
(portrait, arm64-v8a, minSdk 24), playable on desktop for development.

**Latest build:** [Beta 9](https://github.com/DevHuang1/embervale-godot/releases/latest) —
sideload the APK on Android 7.0+, no store account needed.

```
sha256 02f8451e…  Embervale-Beta9-arm64-v8a.apk
```

## What's in it

- **Five seamless realms** — Whispergrove, Bramblewood, Mistfen, Heartwood,
  Moonfen — each with its own palette, weather, enemies and landmarks. Terrain
  carves coherent sand/dirt/grass regions and lays a beach band wherever water
  meets land.
- **Combat with readable telegraphs** — telegraphs match their real hitboxes and
  stay visible under fog and friendly spectacle at every quality tier.
  Low/Medium/High reduce presentation cost only: timing, damage, collision and
  telegraph readability are identical across tiers.
- **Enemies with senses** — orbit/feint/lunge patterns, hearing, anchor leashes,
  elite variants and multi-phase bosses with summons, hazards and phase
  escalation.
- **Forging from blueprints** — the Divining Lens resolves the scan, the forge
  consumes materials exactly once and reports what is missing, and forged
  `relic_<base>` weapons mount through the same visual registry as everything
  else.
- **Satchel, equipment and discovery codex** — inventory, gear comparison,
  a player-following minimap with route/water/relief and a persistent discovery
  fog, and a codex that records what the player has met.
- **Mobile HUD** — one menu at a time, safe-area-aware layout, touch targets
  held to a minimum size, and a quality scaler that owns VFX density, pool and
  trail caps, transient lights, distortion, fog and material detail.

## Playing

**Android:** download the APK from
[Releases](https://github.com/DevHuang1/embervale-godot/releases/latest), open
it, allow "install unknown apps" if asked. It installs over any earlier beta
(same development certificate) and keeps saves.

**Desktop (development):** open `project.godot` in Godot 4.7 and run the main
scene `res://scenes/main/main.tscn`, or:

```sh
godot --path . scenes/main/main.tscn
```

| Action | Desktop | Mobile |
|---|---|---|
| Move | WASD / arrows | Virtual stick |
| Attack | Space / click | Attack button, or tap an enemy |
| Interact | Enter | Contextual button |
| Cinder Lash | Q | Skill button |
| Mend Flame | E | Skill button |
| Divining Lens | F | Scan button |
| Dodge | Shift | Dodge button |
| Jump | C / Ctrl | Jump button |

## Project layout

```
scenes/
  main/main.tscn        entry point (menu, then realm)
  world/                grove, bramblewood, mistfen, heartwood, moonfen
  entities/             hero, enemies, elites, bosses, structures, props
  ui/                   HUD, satchel, forge, shop, dialogs, journal
scripts/
  autoload/             GameState, SceneLoader, AudioManager, StoreManager, ...
  systems/              world streaming, combat, terrain relief, quality, store
  entities/             hero, enemy archetypes, bosses
  world/                realm-specific flow (waterways, boss compounds, ...)
  ui/                   HUD and menu behaviour
assets/
  branding/app_icon/    launcher, adaptive, monochrome, splash (generated)
  textures/stylized/    seven surface families with normal/roughness
  models/               CC0 kits, licence evidence beside each pack
  ui/, fonts/, shaders/, environments/, materials/
backend/                FastAPI entitlement proxy for Play-less purchases
tools/                  offline generators and real-renderer capture harnesses
tests/                  headless contract suites (route, store, UI, VFX, ...)
```

## App identity

The launcher icon, adaptive foreground/background, Android 13 monochrome layer
and boot/splash mark are generated deterministically — no imported art:

```sh
godot --headless --path . --script tools/generate_app_icon.gd
godot --headless --path . --script tests/test_app_icon_assets.gd
```

`export_presets.cfg` is **gitignored** and must be re-pinned before any Android
build: `gradle_build/min_sdk="24"`, `package/name="Embervale"`, all four
`launcher_icons/*` slots and `splash_screen/icon` pointing at
`res://assets/branding/app_icon/*`. Verify every artifact with
`aapt2 dump badging` (minSdk 24, versionCode, `application-label: Embervale`).

## Store

Ember marks are sold through a **hosted RevenueCat funnel backed by Stripe**.
A Play-less build cannot confirm a purchase from the client (the provider secret
must stay server-side), so `backend/` serves the two reads the game needs —
active entitlements and the transaction page — behind a low-privilege app
token. An Android build with the native RevenueCat SDK can use the Test Store
instead, which simulates purchases for device QA.

Rule of thumb: **public artifacts carry no store config** (the shop simply shows
no buy row); keyed and sandbox builds are private QA builds.

- [`docs/REVENUECAT_SETUP.md`](docs/REVENUECAT_SETUP.md) — web funnel, value map, device configuration
- [`docs/REVENUECAT_DASHBOARD_RUNBOOK.md`](docs/REVENUECAT_DASHBOARD_RUNBOOK.md) — dashboard steps and the Render deploy
- [`docs/REVENUECAT_ANDROID_SDK.md`](docs/REVENUECAT_ANDROID_SDK.md) — native Test Store path

## Verification

```sh
godot --headless --path . --editor --quit              # parse/import check
godot --headless --path . --script tests/route_end_to_end_validation.gd
godot --headless --path . --script tests/test_forge_blueprint.gd
godot --headless --path . --script tests/test_app_icon_assets.gd
godot --headless --path . --script tests/test_menu_overlay_exclusion.gd
godot --headless --path . --script tests/test_quality_scaler.gd
godot --headless --path . --script tests/test_realm_visuals.gd
godot --headless --path . --script tests/test_visual_vfx_budgets.gd
python3 -m pytest                                       # backend proxy suite
```

Real-renderer captures (visual acceptance needs a real renderer, never the dummy
one): `tools/capture_realms.gd`, `tools/capture_ui_portrait.gd`,
`tools/capture_weapon_props.gd`, `tools/capture_armor_prop.gd`.

## Docs

Engineering contracts and operator guides live in [`docs/`](docs/):
realm visual grammar, asset conventions, release checklist, the scan-to-forge
migration record, the database schema, and the RevenueCat runbooks.

## License

MIT — see [`LICENSE`](LICENSE). Third-party asset packs are **not** covered by
that license; each keeps its own terms and attribution in
[`ASSET_CREDITS.md`](ASSET_CREDITS.md), summarized in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Checkout terms live in
[`TERMS.md`](TERMS.md).
