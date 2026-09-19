from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from app.config import get_settings
from app.main import app

def test_health():
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_protected_endpoint_requires_auth():
    assert TestClient(app).get("/v1/entitlements").status_code == 401


def _configure_app_token(monkeypatch, token: str = "app-token") -> None:
    monkeypatch.setattr(get_settings(), "store_app_token", token)


def _auth_headers(token: str = "app-token") -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_active_entitlements_requires_the_app_token(monkeypatch):
    _configure_app_token(monkeypatch)
    client = TestClient(app)
    assert client.get("/entitlements/active?customer_id=ev_abc").status_code == 401
    assert client.get("/entitlements/active?customer_id=ev_abc",
                      headers=_auth_headers("wrong-token")).status_code == 401


def test_active_entitlements_refuses_when_the_server_has_no_token(monkeypatch):
    _configure_app_token(monkeypatch, "")
    response = TestClient(app).get("/entitlements/active?customer_id=ev_abc",
                                   headers=_auth_headers())
    assert response.status_code == 401


def test_active_entitlements_rejects_a_hostile_customer_id(monkeypatch):
    _configure_app_token(monkeypatch)
    response = TestClient(app).get("/entitlements/active?customer_id=../admin",
                                   headers=_auth_headers())
    assert response.status_code == 400


def test_active_entitlements_maps_the_provider_payload(monkeypatch):
    _configure_app_token(monkeypatch)
    future = datetime.now(timezone.utc) + timedelta(days=365)
    past = datetime.now(timezone.utc) - timedelta(days=1)
    payload = {
        "subscriber": {
            "entitlements": {
                "embermarks_pouch": {"expires_date": None},
                "embermarks_cache": {"expires_date": future.isoformat()},
                "embermarks_bloodstone": {"expires_date": past.isoformat()},
                "garbage": {"expires_date": "not-a-date"},
            }
        }
    }
    seen: list[str] = []

    def subscriber(customer_id):
        seen.append(customer_id)
        return payload

    monkeypatch.setattr("app.main.revenuecat_subscriber", subscriber)
    response = TestClient(app).get("/entitlements/active?customer_id=ev_abc",
                                   headers=_auth_headers())
    assert response.status_code == 200
    assert seen == ["ev_abc"]
    items = {item["entitlement_id"]: item["expires_at"] for item in response.json()["items"]}
    assert set(items) == {"embermarks_pouch", "embermarks_cache"}
    assert items["embermarks_pouch"] is None
    assert abs(items["embermarks_cache"] - int(future.timestamp() * 1000)) <= 1000


def test_active_entitlements_reports_a_provider_failure(monkeypatch):
    _configure_app_token(monkeypatch)

    def explode(customer_id):
        raise RuntimeError("upstream down")

    monkeypatch.setattr("app.main.revenuecat_subscriber", explode)
    response = TestClient(app).get("/entitlements/active?customer_id=ev_abc",
                                   headers=_auth_headers())
    assert response.status_code == 502
