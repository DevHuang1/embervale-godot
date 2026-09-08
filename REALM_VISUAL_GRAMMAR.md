# Embervale Realm Visual Grammar

This is the composition contract for new terrain, props, lighting, weather,
ambient life, and encounter dressing. It favors readable silhouettes and a
small number of authored focal points over dense random decoration. Gameplay
telegraphs, navigation landmarks, and mobile performance budgets always win.

## Shared composition rules

- Keep the playable route legible from the normal third-person camera: a clear
  foreground edge, a readable midground path, and one background silhouette.
- Build each encounter pocket as **approach → reveal → combat space → reward
  space → exit sightline**. Do not hide the reward behind visual noise.
- Use one dominant material, one supporting material, and one accent material
  per pocket. Reserve high-saturation accents for interactables, enemies, loot,
  and telegraphs.
- Place landmarks at route turns and elevation changes. Repeat a landmark
  motif at a larger distance so the player can orient without a map.
- Keep ambient foliage and life outside combat-readable silhouettes. Ambient
  motion is decorative and must remain capped by the existing quality scaler.

## Realm profiles

| Realm | Foreground / midground / vista | Hue and light | Weather | Traversal pressure | Signature landmarks |
|---|---|---|---|---|---|
| Whispergrove | grass, tiny flowers, mossy stones / gardens, shrubs, old fences / warm tree arches | leaf green, honey gold, muted violet; soft shafts and low contrast | drifting pollen, rare fireflies | gentle discovery; wide teaching spaces | lantern posts, ruined welcome arch, warm spring |
| Bramblewood | thorn grass, roots, bramble clumps / pines, fallen trunks, hedge walls / dark canopy breaks | deep green, bark brown, ember-orange accents; directional dusk | leaf gusts, sparse motes | ambush lanes and thorn pressure; keep exits visible | split-road oak, thorn gate, beacon altar |
| Mistfen | reeds, mud, puddle edges / ponds, dead trees, low bridges / fog banks and water glints | blue-green, slate, pale cyan; cool rim light | layered mist, rain rings, fireflies over water | visibility and status control; use sound and silhouette | ferry post, half-sunk bell, moon pool |
| Heartwood | ash, cracked magma, black grass / ember rocks, burned pines, basalt shelves / volcanic ridges | charcoal, rust red, molten amber; hot local pools | ash fall, heat shimmer, restrained sparks | heat lanes and elite pressure; safe ground must be obvious | cooling shrine, split caldera, forge ruin |
| Moonfen | silver grass, ice reeds, dark mud / frozen ponds, pale trees, crystal shelves / moonlit cliffs | indigo, silver, frost blue, electric violet; high-value rim accents | snow motes, thunder flashes, low aurora | water routes and elemental combinations | moon gate, drowned observatory, storm monolith |

## Asset placement rules

- Grass, flowers, bushes, trees, ponds, rocks, sand, mud, lava, ice, and
  crystals should be placed in authored clusters with a deliberate edge;
  avoid evenly spaced grids and avoid full-screen clutter.
- Large trees, arches, towers, and cliffs are navigation silhouettes, not cover
  that can accidentally occlude attacks. Keep combat pockets below the camera's
  readability threshold.
- Butterflies belong to calm daylight pockets; fireflies belong to dusk, water,
  and shrine pockets. They never compete with loot, objective beacons, or enemy
  telegraphs.
- Weather and ambient VFX should reinforce the realm profile but never alter
  damage, collision, timing, or telegraph visibility across quality tiers.

## Review checklist

- [ ] Can a player name the realm from a screenshot without the HUD?
- [ ] Is the next route direction readable from the normal camera?
- [ ] Does every encounter pocket have an approach, exit, and reward sightline?
- [ ] Are interactables, loot, enemies, and telegraphs the strongest accents?
- [ ] Does Low quality preserve the same route, timing, collision, and combat
  readability as High quality?
- [ ] Has the pocket been checked on the Android target at normal movement speed?
