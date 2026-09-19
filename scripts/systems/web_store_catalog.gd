extends RefCounted
class_name WebStoreCatalog

## === Web ember-mark packs — RevenueCat Funnels + Stripe ===
## Real-money tiers live in the RevenueCat/Stripe dashboard, which owns pricing,
## currency, and receipts. This file declares only the entitlement -> ember-mark
## grant mapping plus the reading a player sees, so store safety audits can
## compile it headlessly and the UI has a single source of truth.
##
## Ember marks buy cosmetics and disclosed scan packs only; no tier grants
## combat power.
##
## `claim_grain` decides the idempotency key:
##   - `transaction`: a repeatable CONSUMABLE. The entitlement stays active
##     forever after the first purchase, so keying on it would refuse every later
##     purchase; the key is the store transaction id instead, which grants each
##     purchase exactly once.
##   - `one_time`: a single grant per entitlement, keyed on the entitlement ALONE
##     (keying it by expiry would let a later body carrying a different
##     `expires_at` mint a second grant).
##   - `expiring`: one grant per period, keyed on the entitlement + expiry.
const GRAIN_TRANSACTION := "transaction"
const GRAIN_ONE_TIME := "one_time"
const GRAIN_EXPIRING := "expiring"

const TIERS: Array[Dictionary] = [
	{
		"id": "ember_pouch",
		"entitlement_id": "embermarks_pouch",
		"product_id": "embermarks_pouch",
		"diamonds": 60,
		"claim_grain": GRAIN_TRANSACTION,
		"name": "Ember Pouch",
		"blurb": "A wanderer's handful of ember marks.",
	},
	{
		"id": "ember_cache",
		"entitlement_id": "embermarks_cache",
		"product_id": "embermarks_cache",
		"diamonds": 180,
		"claim_grain": GRAIN_TRANSACTION,
		"name": "Ember Cache",
		"blurb": "A buried cache — enough for a full cosmetic set.",
	},
	{
		"id": "ember_bloodstone",
		"entitlement_id": "embermarks_bloodstone",
		"product_id": "embermarks_bloodstone",
		"diamonds": 420,
		"claim_grain": GRAIN_TRANSACTION,
		"name": "Bloodstone Reserve",
		"blurb": "The deep-vault reserve, for the whole Glintmonger's case.",
	},
]

static func all() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tier in TIERS:
		rows.append((tier as Dictionary).duplicate(true))
	return rows

static func tier_by_id(tier_id: String) -> Dictionary:
	var wanted := tier_id.strip_edges()
	for tier in TIERS:
		if str(tier.get("id", "")) == wanted:
			return (tier as Dictionary).duplicate(true)
	return {}

static func tier_for_product(product_id: String) -> Dictionary:
	var wanted := product_id.strip_edges()
	for tier in TIERS:
		if product_id_for(tier) == wanted:
			return (tier as Dictionary).duplicate(true)
	return {}

static func tier_for_entitlement(entitlement_id: String) -> Dictionary:
	var wanted := entitlement_id.strip_edges()
	if wanted.is_empty():
		return {}
	for tier in TIERS:
		if str(tier.get("entitlement_id", "")) == wanted:
			return (tier as Dictionary).duplicate(true)
	return {}

## Stable idempotency key. Keyed by entitlement alone for a one-time pack, so a
## different `expires_at` in a later body cannot mint a second grant. An expiring
## tier keys on the expiry so a renewal is granted once per period.
static func record_id_for(entitlement_id: String, expires_at_ms: int,
		grain: String = GRAIN_ONE_TIME) -> String:
	var normalized := entitlement_id.strip_edges()
	if grain == GRAIN_EXPIRING:
		return "revenuecat:%s:%d" % [normalized, expires_at_ms]
	return "revenuecat:%s:%s" % [normalized, GRAIN_ONE_TIME]

## The claim key for a catalogued tier, using the tier's own declared grain.
## Transaction-grain tiers have no entitlement key: they are claimed from the
## transaction list, never from an active entitlement.
static func claim_record_id(tier: Dictionary, expires_at_ms: int) -> String:
	if str(tier.get("claim_grain", GRAIN_ONE_TIME)) == GRAIN_TRANSACTION:
		return ""
	return record_id_for(str(tier.get("entitlement_id", "")), expires_at_ms,
		str(tier.get("claim_grain", GRAIN_ONE_TIME)))

## Repeatable consumables key on the store transaction so every purchase grants
## once and only once.
static func record_id_for_transaction(product_id: String, transaction_id: String) -> String:
	return "revenuecat:%s:txn:%s" % [product_id.strip_edges(), transaction_id.strip_edges()]

static func claim_record_id_for_transaction(tier: Dictionary, transaction_id: String) -> String:
	return record_id_for_transaction(product_id_for(tier), transaction_id)

static func product_id_for(tier: Dictionary) -> String:
	var product := str(tier.get("product_id", "")).strip_edges()
	return product if not product.is_empty() else str(tier.get("entitlement_id", "")).strip_edges()

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen_ids: Dictionary = {}
	var seen_entitlements: Dictionary = {}
	var seen_products: Dictionary = {}
	for tier in TIERS:
		var tier_id := str(tier.get("id", "")).strip_edges()
		var entitlement_id := str(tier.get("entitlement_id", "")).strip_edges()
		var diamonds := int(tier.get("diamonds", 0))
		var grain := str(tier.get("claim_grain", ""))
		if tier_id.is_empty():
			errors.append("Web tier is missing an id")
		if entitlement_id.is_empty():
			errors.append("Web tier is missing an entitlement: %s" % tier_id)
		if diamonds <= 0:
			errors.append("Web tier grants no ember marks: %s" % tier_id)
		if grain not in [GRAIN_TRANSACTION, GRAIN_ONE_TIME, GRAIN_EXPIRING]:
			errors.append("Web tier has an unknown claim grain: %s" % tier_id)
		var product_id := product_id_for(tier)
		if product_id.is_empty():
			errors.append("Web tier is missing a product id: %s" % tier_id)
		elif seen_products.has(product_id):
			errors.append("Duplicate web product id: %s" % product_id)
		seen_products[product_id] = true
		if seen_ids.has(tier_id):
			errors.append("Duplicate web tier id: %s" % tier_id)
		if seen_entitlements.has(entitlement_id):
			errors.append("Duplicate entitlement: %s" % entitlement_id)
		seen_ids[tier_id] = true
		seen_entitlements[entitlement_id] = true
	return errors
