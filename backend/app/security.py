from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from uuid import uuid4
import httpx
import jwt
from fastapi import HTTPException, status
from .config import get_settings


def issue_token(account_id: str) -> str:
    settings = get_settings()
    return jwt.encode({"sub": account_id, "typ": "access", "jti": str(uuid4()), "exp": datetime.now(timezone.utc) + timedelta(seconds=settings.jwt_ttl_seconds)}, settings.jwt_secret, algorithm="HS256")


def issue_refresh_token() -> str:
	return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
	return hashlib.sha256(token.encode("utf-8")).hexdigest()


def verify_oidc_id_token(id_token: str) -> dict:
	settings = get_settings()
	if not settings.oidc_issuer or not settings.oidc_audience or not settings.oidc_jwks_url:
		raise HTTPException(status_code=503, detail="Identity provider is not configured")
	try:
		jwks = httpx.get(settings.oidc_jwks_url, timeout=5.0).json()
		key = jwt.PyJWKClient(settings.oidc_jwks_url).get_signing_key_from_jwt(id_token).key
		claims = jwt.decode(id_token, key, algorithms=["RS256", "ES256"], audience=settings.oidc_audience, issuer=settings.oidc_issuer)
		if claims.get("email_verified") is not True:
			raise ValueError("email not verified")
		return claims
	except (jwt.PyJWTError, httpx.HTTPError, ValueError, KeyError) as exc:
		raise HTTPException(status_code=401, detail="Invalid identity token") from exc


def account_from_token(token: str) -> str:
    try:
        payload = jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
        account_id = str(payload.get("sub", ""))
        if not account_id:
            raise ValueError
        return account_id
    except (jwt.PyJWTError, ValueError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc
