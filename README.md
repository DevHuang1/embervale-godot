# Embervale Mobile — Godot 4 Port

A faithful Godot 4 port of the embervale-rpg web game, with mobile camera scanning and boss battles.

## Features

- **True 3D Grove**: Procedural terrain, moon-shaft lighting, volumetric fog, fireflies, swaying trees
- **Cinder Warden Class**: Auto-combat + Cinder Lash / Mend Flame skills (exact embervale numbers)
- **Quest Progression**: I. Seek Sprite → II. Claim Shard → III. Light Beacon → IV. Complete
- **Inventory & Satchel**: Moss Tonic, Hushling Thorn, Ember Shard with embervale copy
- **Divining Lens**: Camera → object detection → weapon forge with rarity rolls
- **Boss System**: Multi-phase Hushling Matriarch with summons, thorn rain, root prison, bramble storm
- **HUD**: Quest ledger, warmth bar, ember marks, skill cooldowns, loot toasts

## Project Structure

```
embervale-godot/
├── project.godot              # Engine config, autoloads, input map
├── .gitignore
├── scenes/
│   ├── main/main.tscn         # Entry point (loads MainMenu)
│   ├── world/grove.tscn       # Whispergrove 3D scene
│   ├── entities/
│   │   ├── hero.tscn          # Lantern Bearer
│   │   ├── hushling.tscn      # Bramble Sprite enemy
│   │   ├── boss_base.tscn     # Boss template
│   │   └── boss_hushling_matriarch.gd
│   └── ui/
│       ├── hud.tscn           # Quest ledger, warmth, skills, loot
│       ├── satchel.tscn       # Field Satchel (inventory + class)
│       ├── forge_menu.tscn    # Divining Lens camera → forge
│       └── main_menu.tscn     # Lantern-bearer intro
├── scripts/
│   ├── autoload/
│   │   ├── game_state.gd      # Central state (embervale port)
│   │   ├── scan_manager.gd    # Camera → detection → forge
│   │   ├── audio_manager.gd   # Procedural chimes + SFX
│   │   └── input_manager.gd   # Tap-to-move, keys, gestures
│   ├── systems/
│   │   ├── world_manager.gd   # Grove logic, quest triggers
│   │   └── camera_rig.gd      # ArcRotateCamera with shake
│   ├── entities/
│   │   ├── hero.gd            # Tap-to-move, auto-combat, skills
│   │   ├── hushling.gd        # Pattern AI (orbit/feint/lunge/recover)
│   │   ├── boss_base.gd       # Multi-phase boss framework
│   │   └── boss_hushling_matriarch.gd
│   └── ui/
│       ├── hud.gd
│       ├── satchel.gd
│       ├── forge_menu.gd
│       └── main_menu.gd
├── assets/
│   ├── shaders/               # hit_flash, lantern_glow, hero_lantern
│   ├── environments/          # embervale_env, embervale_sky
│   ├── ui/theme.tres
│   └── fonts/                 # Press Start 2P, VT323 (add your own)
└── addons/
```

## Running

1. Open Godot 4.3+
2. Import project: `project.godot`
3. Add font files to `assets/fonts/`:
   - `PressStart2P-Regular.ttf` → import as FontFile
   - `VT323-Regular.ttf` → import as FontFile
3. Run `scenes/main/main.tscn`

## Controls

| Action | Desktop | Mobile |
|--------|---------|--------|
| Move | WASD / Arrow keys | Drag on screen |
| Attack | LMB / Space | Tap enemy |
| Interact | RMB / Enter | Double-tap |
| Cinder Lash | Q | Skill button |
| Mend Flame | E | Skill button |
| Scan | F | Scan button |
| Dodge | Shift (or flick) | Flick quickly |
| Jump | C / Ctrl | - |
| Pause | Escape | - |

## Embervale Parity Checklist

- [x] Moss & Candlewax palette
- [x] Quest stages & copy (verbatim)
- [x] Auto-combat with approach/strike/retaliation
- [x] Passive: every 3rd strike +4 ember damage
- [x] Cinder Lash (16 dmg, 6s cd) + Mend Flame (10 heal, 9s cd)
- [x] XP: 35 first kill → Lv 2, then +10/kill
- [x] Loot: guaranteed cache then tonic rolls
- [x] Quest proximity: shard 1.1 units, beacon 1.45 units
- [x] Hushling AI: orbit/feint/lunge/recover
- [x] Boss phases with unique mechanics
- [x] Camera shake, hit flash, lantern bob
- [x] Procedural chime audio (UI, loot, heal, hit, victory, defeat)

## Next Steps

1. Add `.glb` models for hero, hushling, boss, terrain
2. Replace simulated detection in `ScanManager` with real ML (TensorFlow Lite / MediaPipe)
3. Add particle textures for fireflies, mist, embers
4. Polish UI theme with parchment/ink textures
5. Add save/load system
6. Export templates for iOS/Android