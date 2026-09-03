import json, collections

stages = [
    {"id": "stages.seek_sprite", "chapter": "I. The Quiet Grove", "title": "Find the Hushling", "instruction": "Follow the pale path until the bramble sprite stirs."},
    {"id": "stages.claim_shard", "chapter": "II. A Warm Fragment", "title": "Claim the Ember Shard", "instruction": "The light it dropped is close. Gather it before the mist takes it."},
    {"id": "stages.light_beacon", "chapter": "III. The Way Back", "title": "Restore the Beacon", "instruction": "Carry the Ember Shard to the ruined altar in the north-east grove."},
    {"id": "stages.complete", "chapter": "IV. A Path Relit", "title": "The Grove Remembers", "instruction": "The old road will hold its warmth until the next traveler comes through."},
]

q = collections.OrderedDict()
q["bramblewood.kindling_wood"] = {
    "kind": "side", "chapter": "II. A Warm Fragment", "title": "The Kindling Debt",
    "instruction": "The checkpoint forge is cold. Gather bramble wood and moss fiber to feed it.",
    "giver": "Checkpoint Forge", "auto_grant": True,
    "gates": ["stage.claim_shard"],
    "objectives": [
        {"id": "kindling_wood", "type": "gather", "target": "bramble_wood", "qty": 5, "description": "Gather Bramblewood"},
        {"id": "kindling_fiber", "type": "gather", "target": "moss_fiber", "qty":  4, "description": "Gather Moss Fiber"}
    ],
    "reward": {"gold":  80, "xp":  50, "materials": {"beast_hide":  2}, "flags": ["quest.bramblewood.kindling_wood.done"]}
}

q["bramblewood.thinning_pack"] = {
    "kind": "side", "chapter": "II. A Warm Fragment", "title": "Thin the Thorns",
    "instruction": "The restless brambles gather near the ridge. Cull them so the path holds its warmth.",
    "giver": "The Grove", "auto_grant": False,
    "gates": ["stage.claim_shard", "quest.bramblewood.kindling_wood.done"],
    "objectives": [
        {"id": "kill_hushlings", "type": "kill", "target": "hushling", "qty":  5, "description": "Defeat Hushlings"},
        {"id": "kill_chargers", "type": "kill", "target": "charger", "qty":   2, "description": "Defeat Elder Chargers"}
    ],
    "reward": {"gold":    110, "xp":   70, "materials": {"beast_hide":   3}, "flags": ["quest.bramblewood.thinning_pack.done"]}
}

q["bramblewood.alpha_hoard"] = {
    "kind": "side", "chapter": "II. A Warm Fragment", "title": "The Alpha's Hoard",
    "instruction": "The thorn packs hoard their kill in an old cache. Break it open.",
    "giver": "The Grove", "auto_grant": False,
    "gates": ["stage.claim_shard"],
    "objectives": [
        {"id": "open_alpha_cache", "type": "open_chest", "target": "bramble_elite_cache", "qty":     1, "description": "Open the Alpha's Hoard"}
    ],
    "reward": {"gold": 90, "xp":    60, "materials": {"iron_shard":   2}, "flags": ["quest.bramblewood.alpha_hoard.done"]}
}

q["mistfen.lantern_walk"] ={
    "kind": "side", "chapter": "III. The Way Back", "title": "A Lantern Through Fen",
    "instruction": "The fen drinks light. Gather fen reed and spore dust to keep the lantern's flame fed.",
    "giver": "The Way Station", "auto_grant": True,
    "gates": ["realm.mistfen"],
    "objectives": [
        {"id": "fen_reed_harvest", "type": "gather", "target": "fen_reed", "qty":      6, "description": "Gather Fen Reed"},
        {"id": "spore_dust_harvest", "type": "gather", "target": "spore_dust", "qty":     4, "description": "Gather Spore Dust"}
    ],
    "reward": {"gold":      120, "xp":     80, "materials": {"moonmoss":    1}, "flags": ["quest.mistfen.lantern_walk.done"]}
}

q["heartwood.forge_fire"] ={
    "kind": "side", "chapter": "III. The Way Back", "title": "The Forge Fire",
    "instruction": "Heartwood's forge accepts only proven steel. Raise one of your kit to a new level.",
    "giver": "Heartwood Forge", "auto_grant": True,
    "gates": ["realm.heartwood"],
    "objectives": [
        {"id": "upgrade_once", "type": "upgrade", "target": "", "qty":      1, "description": "Upgrade a weapon or armor piece"}
    ],
    "reward": {"gold":      140, "xp":     90, "materials": {"iron_shard":    2}, "flags": ["quest.heartwood.forge_fire.done"]}
}
q["heartwood.cinderhart"] = {
    "kind": "side", "chapter": "III. The Way Back", "title": "Quench the Colossus",
    "instruction": "The Cinderhart Colossus sleeps in its arena stone. Wake it and put it back to ash.",
    "giver": "Heartwood Forge", "auto_grant": False,
    "gates": ["realm.heartwood", "quest.heartwood.forge_fire.done"],
    "objectives": [
        {"id": "slay_cinderhart", "type": "kill", "target": "cinderhart", "qty":      1, "description": "Defeat the Cinderhart Colossus"}
    ],
    "reward": {"gold":      250, "xp":     200, "diamonds":    2, "materials": {"monster_core":    3}, "flags": ["quest.heartwood.cinderhart.done"]}
}

q["moonfen.oracle_still"] = {
    "kind": "side", "chapter": "IV. A Path Relit", "title": "The Still Oracle",
    "instruction": "The water's quieter children linger where the old moon bleeds. Still them.",
    "giver": "Moonfen Oracle", "auto_grant": True,
    "gates": ["realm.moonfen"],
    "objectives": [
        {"id": "still_fenlings", "type": "kill", "target": "fenling", "qty":       6, "description": "Defeat Fenlings"},
        {"id": "still_leechers", "type": "kill", "target": "relic_leech", "qty":      2, "description": "Defeat Relic Leeches"}
    ],
    "reward": {"gold":      180, "xp":     120, "materials": {"crystal_fragment":    2}, "flags": ["quest.moonfen.oracle_still.done"]}
}

q["moonfen.undertide"] = {
    "kind": "side", "chapter": "IV. A Path Relit", "title": "The Undertide Cache",
    "instruction": "Somewhere beneath the violet water a lunar reliquary waits for a hand that will open it.",
    "giver": "Moonfen Oracle", "auto_grant": False,
    "gates": ["realm.moonfen"],
    "objectives": [
        {"id": "open_lunar_cache", "type": "open_chest", "target": "moonfen_lunar_cache", "qty":      1, "description": "Open the Lunar Reliquary"}
    ],
    "reward": {"gold":      200, "xp":     140, "materials": {"moonmoss":    2}, "flags": ["quest.moonfen.undertide.done"]}
}

root = {
    "schema_version": 1,
    "main_quest": {"stages": stages},
    "quests": [dict(q[k], id=k) for k in q],
}
out = "data/story/quests.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(root, f, indent=2, ensure_ascii=False)