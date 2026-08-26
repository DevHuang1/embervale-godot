# Ember Glass — Landing Page & Game UI Overhaul

## Goal
Rebuild the landing page as a modern web-style "hero" experience over a live 3D backdrop, and roll one coherent **ember-glass** design system across every menu and the HUD, using a real shared Godot `Theme` instead of per-screen ad-hoc styling.

## Locked decisions
| Decision | Choice |
|---|---|
| Art direction | Ember glass: deep-forest dark surfaces, frosted-glass panels, ember-gold glow accents, soft gradients |
| Landing backdrop | Live 3D world behind frosted panels (cinematic camera drift) |
| Scope | Full pass: landing page + shared Theme + all menus inherit + HUD consistency polish |
| Typography | Cinzel (display/CTA) + Manrope (body/UI); PressStart2P survives only as logo wordmark |
| Glass effect | Fake glass (translucency + sheen + grain shader); no realtime blur |

## Design tokens (single source: theme + UiKit)
- Colors: bg deep forest `#0B1712` / panel glass `rgba(10,16,13,0.72)` / ember gold `#F5B841` / warm cream text `#F6ECCE` / sage secondary `#8FAF73` / danger ember-red `#D9523A`
- Radii 12–16px, 1.5px borders `rgba(245,184,65,0.45)` pressed→0.9, soft drop shadows
- Motion: 0.25–0.35s QUAD ease-out entrances, staggered children; hover/tap lift + glow
- Portrait-first: all layouts checked at 1080×1920 with safe-area margins

## Tasks (ordered)

### 1. Fonts
- Download OFL fonts (Google Fonts): Cinzel SemiBold/Bold, Manrope Regular/Medium/SemiBold → `assets/fonts/*.ttf` (+ `.tres` FontFile resources like existing ones).
- Append entries to `assets/models/weapons/LICENSES.md` or new `assets/fonts/LICENSES.md`.

### 2. Shared Theme (`assets/ui/theme.tres`)
- Build out the existing theme: default font Manrope; type variations (`Title`, `Subtitle`, `Body`, `Caption`, `Wordmark`); Button (normal/hover/pressed/disabled/focus StyleBoxFlat + font colors); PanelContainer glass panel; ProgressBar (glass track + ember fill); HSlider/CheckButton; Label colors.
- Set project setting `gui/theme/custom="res://assets/ui/theme.tres"` so every scene inherits.
- New `scripts/ui/ui_kit.gd` (class_name UiKit, static helpers): `glass_panel()`, `accent_button()`, `chip()`, token constants — code paths reuse these so HUD/menus stop hand-rolling duplicate StyleBoxes.

### 3. Glass shader + polish primitives
- `assets/ui/glass_panel.gdshader`: screen-independent fake glass — translucent dark base, top-edge sheen gradient, faint animated grain, 1px inner highlight border. Applied via UiKit.
- Entrance animation helper in UiKit: fade+slide+stagger for container children.

### 4. Landing page rebuild (`scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd`)
- Layout (web hero pattern, bottom-weighted for thumb reach):
  - Top-left small wordmark "EMBERVALE" (PressStart2P, tiny).
  - Center-lower glass hero card: eyebrow "A TALE FROM EMBERVALE", Cinzel title "THE LANTERN BEARER", VT323-free subtitle in Manrope, primary CTA "BEGIN A NEW TALE" (large ember-gradient button), secondary row Continue / Settings.
  - Footer control-hints line kept, Caption variation.
  - Version chip bottom-right.
- Behavior: keep `_check_continue_availability`; if a save exists, CTA press shows an inline confirm card ("Begin anew? Current tale will fade.") with Confirm/Back instead of instant reset. Remove permanently-dead SATCHEL button from menu (satchel stays field-only via HUD).
- Staggered entrance animations via UiKit helper; buttons get hover/press glow.

### 5. Live 3D backdrop (`scenes/ui/menu_backdrop.tscn` + `.gd`)
- Instantiates the real `grove.tscn`, then contains it: hide its `HUD`, free/disable enemy entities & WorldManager ticking (`set_physics_process(false)` + entity process off), leave environment/terrain/trees/fireflies/Hero idle with lantern lit.
- Own `MenuCamera` node does a slow drift/orbit around Hero spawn (no SpringArm game camera active).
- Layered 2D vignette + drifting ember particles overlay between 3D and menu panels.
- Safety: wrap containment in checks; if anything fails, fall back to the old flat gradient ColorRect so the menu never renders broken.
- `main_menu.gd` owns backdrop lifecycle; on play → brief fade (reuse `screen_fx.gd` if suitable, else CanvasLayer fade) → `change_scene_to_file("grove.tscn")` exactly as today.

### 6. Menu screens restyle (inherit theme, delete ad-hoc styles)
- `settings_menu`, `shop_menu`, `satchel`, `forge_menu`, `stats_screen`, `diamond_shop`, `boss_altar`: swap hardcoded panels/buttons for theme + UiKit glass; unify paddings, title style (Cinzel), close/back affordances. Keep all logic/signals untouched.
- Where a script builds StyleBoxFlat inline, replace with UiKit calls.

### 7. HUD consistency polish (light touch — recently redesigned)
- Migrate `_panel_style`/`_style_button`/`_style_chip` in `hud.gd` to UiKit equivalents (same visual language, single source).
- Align fonts to new hierarchy (Cinzel titles on ledger/boss bar, Manrope body); spacing/rounding matched to tokens; toast animations kept.

### 8. Validation
- Headless boot smoke (new `tests/test_ui_shell.gd`): instantiate `main.tscn`; assert menu nodes/theme applied (button has non-default stylebox), backdrop present, simulate CTA-with-save confirm path, then Begin → grove loads with HUD visible.
- Run existing suites and require green: `test_combat_recovery.gd`, `test_anim_state_reset.gd`, `test_weapon_mount.gd` (weapon equip touches HUD signals).
- Manual checklist (desktop run): menu entrance anim, backdrop drift, play transition, each menu open/close, portrait 1080×1920 layout.

## Risks
- Grove-in-menu containment leaks simulation (enemies roaming under menu) → mitigated by explicit disable list + smoke assertion that enemies are absent/inert in menu state.
- Theme override ordering: code-level `add_theme_*_override` beats Theme; HUD keeps overrides until migrated in task 7.
- Font metrics shift label wrapping (VT323→Manrope wider) → verify every menu at target resolution during manual pass.
- Mobile GPU cost: backdrop is one extra rendered world; acceptable since gameplay world already renders same content.

## Out of scope
- Realtime blur, desktop/tablet layouts beyond portrait scaling, satchel field-only gating change, any gameplay/AI/save-format changes, new music.
