# Embervale Golden Route

This is the reference 20–30 minute route for the first polished vertical slice.
It is a pacing contract, not a promise that headless tests replace real-rendered
or Android playtesting.

| Beat | Target | Player intent | Required authored signal | State / reward | Recovery point |
|---|---:|---|---|---|---|
| Arrival at Whispergrove | 0:00–1:30 | Learn where to look and move | Lantern path, welcome arch, calm arrival framing | `grove_arrival`; no forced menu | Arrival checkpoint |
| First living clue | 1:30–4:00 | Follow the pale path | Butterfly/foliage motion and a visible Hushling stir | Chapter I objective appears | Respawn at arrival |
| First readable fight | 4:00–7:00 | Learn target, dodge, and one weapon verb | One enemy role, red telegraph, clear hit reaction | XP, gold, first material | Fight pocket reset |
| Gathering ritual | 7:00–10:00 | Understand why materials matter | Two marked gathering nodes near the route | Bramblewood materials and crafting explanation | Last safe landmark |
| First upgrade decision | 10:00–13:00 | Compare and strengthen a build | Forge preview shows before/after held weapon | Weapon upgrade and visible hand presentation | Grove checkpoint |
| Bramblewood approach | 13:00–16:00 | Read escalation and choose space | Landmark silhouette, authored encounter pocket, music danger rise | Optional material/scan-fragment reward | Route checkpoint |
| Elite lesson | 16:00–20:00 | Apply dodge, interrupt, and status knowledge | One elite role plus one supporting role; bounded telegraphs | Valuable drop with build context | Elite pocket reset |
| Matriarch reveal | 20:00–21:00 | Recognize the boss rules | Skippable reveal, arena readability, threat hierarchy | Boss music state and objective lock | Boss arena entry |
| Boss phases | 21:00–26:00 | Learn, test, and master patterns | Guard break, vulnerability window, phase escalation, safe space | Boss reward choice; no duplicate first-clear reward | Phase-safe reset |
| Unlock and aftermath | 26:00–30:00 | See the long-term goal | Victory/reward reveal, forge prompt, cyan marsh-lights | Moonfen unlock; Crown upgrade objective | `beacon_relit` |

## Route rules

- Every beat must have one dominant player question and one next action.
- Menus pause the world and return control cleanly; no tutorial overlay may hide
  a combat telegraph or be required to understand the route.
- Combat damage, collision, and telegraph timing are invariant across quality
  tiers. Lower tiers reduce presentation cost only.
- Death, reload, scene transition, and repeated interaction must return the
  player to the last meaningful recovery point without duplicating rewards.
- The route is accepted only after a real-rendered playthrough confirms pacing,
  visibility, touch input, audio transitions, and camera handoff on Android.

## Playtest capture sheet

Record elapsed time, death location, first-confusion moment, objective clarity,
upgrade comprehension, shop/scan trust, boss readability, and whether the
player can state the next action after each beat. A green structural test is
evidence of a contract; it is not visual or device acceptance.
