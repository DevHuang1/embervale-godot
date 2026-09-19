# Embervale Asset Conventions

These conventions keep downloaded art replaceable without changing gameplay
data or save files.

## Stable identity

- Gameplay uses lowercase `snake_case` semantic IDs, never source filenames.
- IDs are immutable after release; a replacement changes only the resolved
  resource path.
- Pack folders retain the provider name and version evidence, for example
  `assets/models/kenney_nature/`.

## Folders and prefabs

- Imported models: `assets/models/<pack>/Models/`.
- Imported textures: adjacent `Textures/` or `assets/textures/<family>/`.
- Ambient non-interactive art: `assets/ambient/<pack>/`.
- Authored runtime prefabs: `scenes/entities/`, `scenes/world/`, and
  `scenes/ui/`; gameplay data must resolve them by semantic ID.
- Do not put provider paths in save data.

## Geometry and import

- Every catalog path is project-local, loadable, and has an owner/use case.
- Root scale and pivot are reviewed at gameplay scale; replacement prefabs
  normalize their authored scale before attachment.
- LOD is presentation-only. It must not alter hitboxes, telegraphs, damage, or
  interaction ranges.
- Gameplay collision belongs to the authored prefab, not an untrusted imported
  mesh. Visual-only props use no gameplay collision layer.

## Sockets and replacement contract

- Equipment attaches only to `hand_l`, `hand_r`, or `back` sockets.
- Socket transforms are authored by the hero/owner prefab; assets do not
  overwrite gameplay sockets.
- `ContentRegistry.resolve_asset_path()` is the replacement boundary. Fallback
  paths remain valid until a replacement is available.

## Body armor models

- Body armor defaults to the procedural builders in `hero.gd`. An imported
  armor asset is wired by adding an `ArmorVisualRegistry` record with
  `kind: "model"`; the hero then mounts that rigid prop on a skeleton bone.
- Model records carry `path`, `bone` (default `Torso`), `offset`,
  `rotation_degrees`, and `length`. Nothing is skinned: the piece is authored
  around its own pivot and seated by the record's transform.
- Size is measured from the model's own bounds and normalized to `length`
  metres, so replacement assets never need hand-tuned scale constants.
- License evidence is mandatory before a record ships; add it to
  `assets/models/LICENSES.md` with source, pack page, and license, and add the
  matching entry to `AssetIntakeCatalog`.
- Review seat and scale with
  `godot --path . --script tools/capture_armor_prop.gd --rendering-driver metal`
  before wiring the record; `tests/test_armor_visuals.gd` guards the contract.
