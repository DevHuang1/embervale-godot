import hashlib
import hmac
import time
import httpx
from .config import get_settings


def verify_revenuecat_signature(raw: bytes, header: str) -> bool:
    secret = get_settings().revenuecat_webhook_secret
    if not secret or not header.startswith("t="):
        return False
    values = dict(part.split("=", 1) for part in header.split(",") if "=" in part)
    try:
        timestamp = int(values["t"])
        if abs(int(time.time()) - timestamp) > 300:
            return False
        expected = hmac.new(secret.encode(), f"{timestamp}.".encode() + raw, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, values.get("v1", ""))
    except (KeyError, ValueError):
        return False


def verify_stripe_signature(raw: bytes, header: str) -> bool:
    # Stripe's official SDK performs timestamp and scheme parsing. Keep this
    # helper conservative for environments where the SDK key is not configured.
    secret = get_settings().stripe_webhook_secret
    if not secret or not header:
        return False
    try:
        import stripe
        stripe.WebhookSignature.verify_header(raw, header, secret, tolerance=300)
        return True
    except Exception:
        return False


def revenuecat_subscriber(app_user_id: str) -> dict:
	settings = get_settings()
	if not settings.revenuecat_api_key or not app_user_id:
		raise RuntimeError("RevenueCat is not configured")
	response = httpx.get(
		f"https://api.revenuecat.com/v1/subscribers/{app_user_id}",
		headers={"Authorization": f"Bearer {settings.revenuecat_api_key}"},
		timeout=5.0,
	)
	response.raise_for_status()
	return response.json()
