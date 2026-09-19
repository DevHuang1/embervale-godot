import hmac
import json
import logging
import hashlib
import re
import time
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session
from .config import get_settings
from .db import Base, engine, get_db
from .models import Account, AuditLog, Entitlement, MutationLedger, PriceVariant, Product, ProviderEvent, ProviderIdentity, PurchaseLedger, SessionRecord
from .providers import revenuecat_subscriber, verify_revenuecat_signature, verify_stripe_signature
from .schemas import AccountResponse, ActiveEntitlementItem, ActiveEntitlementsResponse, CheckoutRequest, EntitlementResponse, MutationRequest, OidcExchangeRequest, ProviderLinkRequest, RefreshRequest, TransactionItem, TransactionsResponse
from .security import account_from_token, hash_refresh_token, issue_refresh_token, issue_token, verify_oidc_id_token

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("embervale-api")
settings = get_settings()
app = FastAPI(title="Embervale API", version="0.1.0", docs_url="/docs" if settings.docs_enabled else None, redoc_url=None, openapi_url="/openapi.json" if settings.docs_enabled else None)
app.add_middleware(CORSMiddleware, allow_origins=settings.origins, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
bearer = HTTPBearer(auto_error=False)
_rate_windows: dict[str, list[float]] = {}

@app.middleware("http")
async def security_middleware(request: Request, call_next):
	content_length = int(request.headers.get("content-length", "0") or 0)
	if request.method in ["POST", "PUT", "PATCH"] and content_length > settings.max_request_bytes:
		return JSONResponse({"detail": "Request too large"}, status_code=413)
	key = hashlib.sha256(f"{request.client.host if request.client else 'unknown'}:{request.url.path}".encode()).hexdigest()
	now_value = time.time()
	window = [stamp for stamp in _rate_windows.get(key, []) if now_value - stamp < 60.0]
	if len(window) >= settings.rate_limit_per_minute:
		return JSONResponse({"detail": "Too many requests"}, status_code=429, headers={"Retry-After": "60"})
	window.append(now_value)
	_rate_windows[key] = window
	response = await call_next(request)
	response.headers["X-Content-Type-Options"] = "nosniff"
	response.headers["X-Frame-Options"] = "DENY"
	response.headers["Referrer-Policy"] = "no-referrer"
	cacheable_path = not request.url.path.startswith("/v1") and not request.url.path.startswith("/entitlements/")
	response.headers["Cache-Control"] = "no-cache" if cacheable_path else "no-store"
	return response

def audit(db: Session, request: Request | None, account_id: str | None, event: str, metadata: dict | None = None) -> None:
	ip = request.client.host if request and request.client else "unknown"
	request_id = request.headers.get("X-Request-ID", str(uuid4())) if request else str(uuid4())
	db.add(AuditLog(account_id=account_id, event=event, request_id=request_id, ip_hash=hashlib.sha256(ip.encode()).hexdigest(), event_metadata=metadata or {}))


@app.on_event("startup")
def startup() -> None:
    if settings.environment != "production":
        Base.metadata.create_all(engine)


def current_account(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)) -> str:
	if credentials is None:
		raise HTTPException(status_code=401, detail="Authentication required")
	account_id = account_from_token(credentials.credentials)
	account = db.get(Account, account_id)
	if account is None or account.disabled or not account.verified:
		raise HTTPException(status_code=401, detail="Invalid session")
	return account_id


# RevenueCat app user ids this route will look up. The game mints `ev_<hex>`
# ids, but the pattern stays permissive for dashboards that use e-mail-shaped
# ids while refusing anything that could reshape the upstream URL.
_APP_USER_ID = re.compile(r"^[A-Za-z0-9_$:.\-@+]{1,128}$")
# Bound the page the device parses; the client caps its own list at 100 too.
_MAX_TRANSACTIONS = 100


def current_store_app(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> None:
	"""Authenticates the shipped game client on the read-only store route.

	The client holds a low-privilege app token. It can read the entitlements of
	the RevenueCat customer it names and nothing else; the provider secret stays
	on the server. An unset server token refuses every request rather than
	falling open, and the comparison is constant-time.
	"""
	expected = settings.store_app_token
	presented = credentials.credentials if credentials is not None else ""
	if not expected or not presented or not hmac.compare_digest(expected, presented):
		raise HTTPException(status_code=401, detail="Authentication required")


@app.get("/entitlements/active", response_model=ActiveEntitlementsResponse)
def active_entitlements(customer_id: str, _: None = Depends(current_store_app)) -> ActiveEntitlementsResponse:
	"""Read-through to RevenueCat in the `active_entitlements` list shape.

	The game parses this response with the same parser it uses for RevenueCat's
	own API, so the device never needs a provider secret. The route is read-only
	on purpose: granting stays in the app's claim ledger, keyed by entitlement.
	"""
	if not _APP_USER_ID.match(customer_id):
		raise HTTPException(status_code=400, detail="Invalid customer id")
	try:
		subscriber = revenuecat_subscriber(customer_id)
	except Exception as exc:
		logger.warning("RevenueCat lookup failed for a store refresh: %s", type(exc).__name__)
		raise HTTPException(status_code=502, detail="Entitlement provider unavailable") from exc
	entitlements = subscriber.get("subscriber", {}).get("entitlements", {})
	if not isinstance(entitlements, dict):
		raise HTTPException(status_code=502, detail="Entitlement provider unavailable")
	now_value = datetime.now(timezone.utc)
	items: list[ActiveEntitlementItem] = []
	for entitlement_id, value in entitlements.items():
		if not isinstance(value, dict):
			continue
		expires_at: int | None = None
		expires_date = value.get("expires_date")
		if expires_date:
			try:
				expiry = datetime.fromisoformat(str(expires_date).replace("Z", "+00:00"))
			except ValueError:
				continue
			if expiry.tzinfo is None:
				expiry = expiry.replace(tzinfo=timezone.utc)
			if expiry <= now_value:
				continue
			expires_at = int(expiry.timestamp() * 1000)
		items.append(ActiveEntitlementItem(entitlement_id=str(entitlement_id), expires_at=expires_at))
	return ActiveEntitlementsResponse(items=items)


@app.get("/transactions", response_model=TransactionsResponse)
def non_subscription_transactions(customer_id: str, _: None = Depends(current_store_app)) -> TransactionsResponse:
	"""The customer's one-time purchases, in the game's transaction shape.

	A repeatable pack (a consumable) is granted once per purchase, and the only
	stable key for that is the store transaction id — the entitlement stays
	active forever after the first buy, so an entitlement read alone cannot tell
	a second purchase from the first. Only ids and the purchase instant leave
	the server; no receipt, price, or payment detail is exposed.
	"""
	if not _APP_USER_ID.match(customer_id):
		raise HTTPException(status_code=400, detail="Invalid customer id")
	try:
		subscriber = revenuecat_subscriber(customer_id)
	except Exception as exc:
		logger.warning("RevenueCat transaction lookup failed: %s", type(exc).__name__)
		raise HTTPException(status_code=502, detail="Entitlement provider unavailable") from exc
	non_subscriptions = subscriber.get("subscriber", {}).get("non_subscriptions", {})
	if not isinstance(non_subscriptions, dict):
		raise HTTPException(status_code=502, detail="Entitlement provider unavailable")
	items: list[TransactionItem] = []
	for product_id, entries in non_subscriptions.items():
		if not isinstance(entries, list):
			continue
		for entry in entries:
			if not isinstance(entry, dict):
				continue
			transaction_id = str(entry.get("id", "")).strip()
			if not transaction_id:
				continue
			purchased_at = 0
			purchase_date = entry.get("purchase_date")
			if purchase_date:
				try:
					parsed = datetime.fromisoformat(str(purchase_date).replace("Z", "+00:00"))
					purchased_at = int(parsed.timestamp() * 1000)
				except (ValueError, OverflowError):
					purchased_at = 0
			items.append(TransactionItem(
				product_id=str(product_id),
				transaction_id=transaction_id,
				purchased_at=purchased_at,
			))
			if len(items) >= _MAX_TRANSACTIONS:
				return TransactionsResponse(items=items)
	return TransactionsResponse(items=items)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "environment": settings.environment}


@app.post("/v1/auth/exchange", response_model=AccountResponse)
def exchange_oidc(body: OidcExchangeRequest, request: Request, db: Session = Depends(get_db)) -> AccountResponse:
	claims = verify_oidc_id_token(body.id_token)
	provider_user_id = str(claims.get("sub", ""))
	if not provider_user_id:
		raise HTTPException(status_code=401, detail="Invalid identity token")
	identity = db.scalar(select(ProviderIdentity).where(ProviderIdentity.provider == "oidc", ProviderIdentity.provider_user_id == provider_user_id))
	if identity:
		account = db.get(Account, identity.account_id)
	else:
		account = Account(verified=True)
		db.add(account)
		db.flush()
		db.add(ProviderIdentity(account_id=account.id, provider="oidc", provider_user_id=provider_user_id))
	if account is None or account.disabled or not account.verified:
		raise HTTPException(status_code=403, detail="Account unavailable")
	refresh = issue_refresh_token()
	db.add(SessionRecord(account_id=account.id, refresh_hash=hash_refresh_token(refresh), family_id=str(uuid4()), expires_at=datetime.now(timezone.utc) + timedelta(days=30)))
	audit(db, request, account.id, "auth.exchange")
	db.commit()
	return AccountResponse(account_id=account.id, access_token=issue_token(account.id), refresh_token=refresh)

@app.post("/v1/auth/refresh", response_model=AccountResponse)
def refresh_session(body: RefreshRequest, request: Request, db: Session = Depends(get_db)) -> AccountResponse:
	session = db.scalar(select(SessionRecord).where(SessionRecord.refresh_hash == hash_refresh_token(body.refresh_token)))
	now_value = datetime.now(timezone.utc)
	if session is None or session.revoked_at is not None or session.expires_at <= now_value:
		audit(db, request, None, "auth.refresh_rejected")
		db.commit()
		raise HTTPException(status_code=401, detail="Invalid session")
	account = db.get(Account, session.account_id)
	if account is None or account.disabled or not account.verified:
		raise HTTPException(status_code=401, detail="Invalid session")
	session.revoked_at = now_value
	refresh = issue_refresh_token()
	db.add(SessionRecord(account_id=account.id, refresh_hash=hash_refresh_token(refresh), family_id=session.family_id, expires_at=now_value + timedelta(days=30)))
	audit(db, request, account.id, "auth.refresh")
	db.commit()
	return AccountResponse(account_id=account.id, access_token=issue_token(account.id), refresh_token=refresh)

@app.post("/v1/auth/logout")
def logout(body: RefreshRequest, request: Request, db: Session = Depends(get_db)) -> dict:
	session = db.scalar(select(SessionRecord).where(SessionRecord.refresh_hash == hash_refresh_token(body.refresh_token)))
	if session:
		session.revoked_at = datetime.now(timezone.utc)
		audit(db, request, session.account_id, "auth.logout")
	db.commit()
	return {"logged_out": True}

@app.get("/v1/me")
def me(account_id: str = Depends(current_account), db: Session = Depends(get_db)) -> dict:
	account = db.get(Account, account_id)
	if account is None or account.disabled or not account.verified:
		raise HTTPException(status_code=401, detail="Invalid session")
	return {"account_id": account.id, "server_revision": account.server_revision}


@app.post("/v1/account/providers")
def link_provider(body: ProviderLinkRequest, account_id: str = Depends(current_account), db: Session = Depends(get_db)) -> dict:
    existing = db.scalar(select(ProviderIdentity).where(ProviderIdentity.provider == body.provider, ProviderIdentity.provider_user_id == body.provider_user_id))
    if existing and existing.account_id != account_id:
        raise HTTPException(status_code=409, detail="Provider identity already linked")
    if not existing:
        db.add(ProviderIdentity(account_id=account_id, provider=body.provider, provider_user_id=body.provider_user_id))
        db.commit()
    return {"linked": True, "provider": body.provider}


@app.get("/v1/entitlements", response_model=list[EntitlementResponse])
def entitlements(account_id: str = Depends(current_account), db: Session = Depends(get_db)) -> list[Entitlement]:
    return list(db.scalars(select(Entitlement).where(Entitlement.account_id == account_id)))


@app.post("/v1/entitlements/restore", response_model=list[EntitlementResponse])
def restore_entitlements(request: Request, account_id: str = Depends(current_account), db: Session = Depends(get_db)) -> list[Entitlement]:
	identity = db.scalar(select(ProviderIdentity).where(ProviderIdentity.account_id == account_id, ProviderIdentity.provider == "revenuecat"))
	if identity is None:
		raise HTTPException(status_code=409, detail="RevenueCat account is not linked")
	try:
		subscriber = revenuecat_subscriber(identity.provider_user_id)
	except Exception as exc:
		audit(db, request, account_id, "entitlement.restore_failed")
		db.commit()
		raise HTTPException(status_code=502, detail="Entitlement provider unavailable") from exc
	active = subscriber.get("subscriber", {}).get("entitlements", {})
	for entitlement_id, value in active.items():
		expires_at = None
		if value.get("expires_date"):
			expires_at = datetime.fromisoformat(str(value["expires_date"]).replace("Z", "+00:00"))
		row = db.scalar(select(Entitlement).where(Entitlement.account_id == account_id, Entitlement.entitlement_id == str(entitlement_id)))
		if row is None:
			row = Entitlement(account_id=account_id, entitlement_id=str(entitlement_id), active=expires_at is None or expires_at > datetime.now(timezone.utc), provider="revenuecat", expires_at=expires_at)
			db.add(row)
		else:
			row.active = expires_at is None or expires_at > datetime.now(timezone.utc)
			row.expires_at = expires_at
	audit(db, request, account_id, "entitlement.restore")
	db.commit()
	return list(db.scalars(select(Entitlement).where(Entitlement.account_id == account_id)))


@app.get("/v1/catalog")
def catalog(db: Session = Depends(get_db)) -> list[dict]:
    rows = db.execute(select(Product, PriceVariant).join(PriceVariant, PriceVariant.product_id == Product.id).where(Product.active.is_(True), PriceVariant.active.is_(True))).all()
    return [{"product_id": product.id, "kind": product.kind, "price_variant_id": price.id, "provider": price.provider, "region": price.region} for product, price in rows]


@app.post("/v1/sync")
def sync(body: list[MutationRequest], account_id: str = Depends(current_account), db: Session = Depends(get_db)) -> list[dict]:
	if len(body) > settings.max_sync_batch:
		raise HTTPException(status_code=413, detail="Sync batch too large")
	allowed_actions = {"purchase", "sell", "craft", "upgrade_weapon", "upgrade_armor", "equip", "complete_quest", "consume_scan", "claim_reward", "refund"}
	results: list[dict] = []
	for mutation in body:
		if mutation.action not in allowed_actions or any(key in json.dumps(mutation.payload).lower() for key in ["gold", "diamonds", "balance", "inventory", "entitlement", "reward", "price", "stats"]):
			results.append({"id": mutation.id, "status": "rejected", "error": "authoritative fields are not accepted", "server_revision": 0})
			continue
		existing = db.get(MutationLedger, mutation.id)
		if existing and existing.account_id != account_id:
			raise HTTPException(status_code=409, detail="Mutation belongs to another account")
		if not existing:
			existing = MutationLedger(id=mutation.id, account_id=account_id, action=mutation.action, payload=mutation.payload, status="accepted")
			db.add(existing)
			db.commit()
		results.append({"id": mutation.id, "status": existing.status, "server_revision": 0})
	return results


@app.post("/v1/stripe/checkout")
def stripe_checkout(body: CheckoutRequest, account_id: str = Depends(current_account), db: Session = Depends(get_db)) -> dict:
    if body.distribution == "android" and not settings.stripe_alternative_billing_enabled:
        raise HTTPException(status_code=403, detail="Stripe Android billing is disabled")
    price = db.get(PriceVariant, body.price_variant_id)
    if not price or price.provider != "stripe" or not price.active:
        raise HTTPException(status_code=404, detail="Unknown Stripe price")
    if not settings.stripe_secret_key:
        raise HTTPException(status_code=503, detail="Stripe is not configured")
    import stripe
    stripe.api_key = settings.stripe_secret_key
    session = stripe.checkout.Session.create(line_items=[{"price": price.provider_price_id, "quantity": 1}], mode="payment", success_url=settings.stripe_success_url, cancel_url=settings.stripe_cancel_url, metadata={"account_id": account_id, "price_variant_id": price.id}, idempotency_key=f"checkout:{account_id}:{price.id}")
    return {"checkout_url": session.url, "session_id": session.id}


@app.post("/v1/webhooks/revenuecat")
async def revenuecat_webhook(request: Request, x_revenuecat_webhook_signature: str = Header(default=""), db: Session = Depends(get_db)) -> dict:
    raw = await request.body()
    if not verify_revenuecat_signature(raw, x_revenuecat_webhook_signature):
        raise HTTPException(status_code=401, detail="Invalid RevenueCat signature")
    payload = json.loads(raw)
    event = payload.get("event", {})
    event_id = str(event.get("id", ""))
    if not event_id:
        raise HTTPException(status_code=400, detail="Missing event id")
    if db.get(ProviderEvent, event_id):
        return {"accepted": True, "duplicate": True}
    provider_user_id = str(event.get("app_user_id", ""))
    identity = db.scalar(select(ProviderIdentity).where(ProviderIdentity.provider == "revenuecat", ProviderIdentity.provider_user_id == provider_user_id))
    if identity:
        event_type = str(event.get("type", "")).upper()
        active = event_type not in {"CANCELLATION", "EXPIRATION", "BILLING_ISSUE", "REFUND"}
        for entitlement_id in event.get("entitlement_ids", []):
            row = db.scalar(select(Entitlement).where(Entitlement.account_id == identity.account_id, Entitlement.entitlement_id == str(entitlement_id)))
            if row:
                row.active = active
                row.provider = "revenuecat"
            else:
                db.add(Entitlement(account_id=identity.account_id, entitlement_id=str(entitlement_id), active=active, provider="revenuecat"))
        transaction_id = str(event.get("transaction_id", ""))
        if transaction_id:
            db.merge(PurchaseLedger(provider_purchase_id=transaction_id, account_id=identity.account_id, provider="revenuecat", product_id=str(event.get("product_id", "")), status="active" if active else "revoked", purchase_metadata=event))
    db.add(ProviderEvent(provider_event_id=event_id, provider="revenuecat", event_type=str(event.get("type", "unknown")), payload=payload, processed=True))
    db.commit()
    return {"accepted": True}


@app.post("/v1/webhooks/stripe")
async def stripe_webhook(request: Request, stripe_signature: str = Header(default="stripe-signature"), db: Session = Depends(get_db)) -> dict:
    raw = await request.body()
    if not verify_stripe_signature(raw, stripe_signature):
        raise HTTPException(status_code=401, detail="Invalid Stripe signature")
    import stripe
    event = stripe.Event.construct_from(json.loads(raw), settings.stripe_secret_key)
    event_id = str(event.get("id", ""))
    if db.get(ProviderEvent, event_id):
        return {"accepted": True, "duplicate": True}
    event_payload = json.loads(raw)
    event_object = event_payload.get("data", {}).get("object", {})
    event_type = str(event_payload.get("type", "unknown"))
    metadata = event_object.get("metadata", {}) if isinstance(event_object, dict) else {}
    account_id = str(metadata.get("account_id", ""))
    if account_id and event_type == "checkout.session.completed":
        db.merge(PurchaseLedger(provider_purchase_id=str(event_object.get("payment_intent", event_id)), account_id=account_id, provider="stripe", product_id=str(metadata.get("price_variant_id", "")), status="active", purchase_metadata=event_object))
    db.add(ProviderEvent(provider_event_id=event_id, provider="stripe", event_type=event_type, payload=event_payload, processed=True))
    db.commit()
    return {"accepted": True}
