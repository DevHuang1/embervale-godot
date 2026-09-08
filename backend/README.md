# Embervale Backend

FastAPI service for account identity, authoritative player sync, RevenueCat and
Stripe provider events, and entitlement reconciliation. It is intentionally
separate from the Godot project runtime so provider secrets never ship in the
Android client.

Run locally with `uvicorn app.main:app --reload` after copying `.env.example`.
