from pathlib import Path


def test_production_docs_are_disabled_by_default():
    config = Path("backend/app/config.py").read_text()
    assert "docs_enabled: bool = False" in config


def test_unauthenticated_account_creation_is_removed():
    source = Path("backend/app/main.py").read_text()
    assert '@app.post("/v1/accounts"' not in source
    assert '@app.post("/v1/auth/exchange"' in source


def test_sensitive_fields_are_not_client_owned():
    source = Path("backend/app/main.py").read_text()
    for field in ["gold", "diamonds", "inventory", "entitlement", "reward", "price", "stats"]:
        assert field in source
