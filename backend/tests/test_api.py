from fastapi.testclient import TestClient
from app.main import app

def test_health():
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_protected_endpoint_requires_auth():
    assert TestClient(app).get("/v1/entitlements").status_code == 401
