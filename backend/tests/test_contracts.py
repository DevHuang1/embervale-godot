import hashlib
import hmac
import time
from app.config import get_settings
from app.providers import verify_revenuecat_signature

def test_revenuecat_signature_requires_recent_raw_body(monkeypatch):
    monkeypatch.setattr(get_settings(), "revenuecat_webhook_secret", "test-secret")
    body = b'{"event":{"id":"evt_1"}}'
    timestamp = str(int(time.time()))
    digest = hmac.new(b"test-secret", f"{timestamp}.".encode() + body, hashlib.sha256).hexdigest()
    assert verify_revenuecat_signature(body, f"t={timestamp},v1={digest}")
    assert not verify_revenuecat_signature(body, "t=1,v1=bad")
