from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .db import Base


def now() -> datetime:
    return datetime.now(timezone.utc)


class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    server_revision: Mapped[int] = mapped_column(Integer, default=0)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    disabled: Mapped[bool] = mapped_column(Boolean, default=False)


class ProviderIdentity(Base):
    __tablename__ = "provider_identities"
    __table_args__ = (UniqueConstraint("provider", "provider_user_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    provider: Mapped[str] = mapped_column(String(32))
    provider_user_id: Mapped[str] = mapped_column(String(255))


class SessionRecord(Base):
    __tablename__ = "sessions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    refresh_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    family_id: Mapped[str] = mapped_column(String(36), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class AuditLog(Base):
    __tablename__ = "audit_log"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True, index=True)
    event: Mapped[str] = mapped_column(String(80), index=True)
    request_id: Mapped[str] = mapped_column(String(64), index=True)
    ip_hash: Mapped[str | None] = mapped_column(String(128), nullable=True)
    event_metadata: Mapped[dict] = mapped_column("metadata", JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class RateLimitEvent(Base):
    __tablename__ = "rate_limit_events"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    key_hash: Mapped[str] = mapped_column(String(128), index=True)
    route: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Entitlement(Base):
    __tablename__ = "entitlements"
    __table_args__ = (UniqueConstraint("account_id", "entitlement_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    entitlement_id: Mapped[str] = mapped_column(String(128))
    active: Mapped[bool] = mapped_column(Boolean, default=False)
    provider: Mapped[str] = mapped_column(String(32))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)


class ProviderEvent(Base):
    __tablename__ = "provider_events"
    provider_event_id: Mapped[str] = mapped_column(String(255), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), index=True)
    event_type: Mapped[str] = mapped_column(String(128))
    payload: Mapped[dict] = mapped_column(JSON)
    processed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Product(Base):
    __tablename__ = "products"
    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    kind: Mapped[str] = mapped_column(String(32))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class PriceVariant(Base):
    __tablename__ = "price_variants"
    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"), index=True)
    provider: Mapped[str] = mapped_column(String(32))
    provider_price_id: Mapped[str] = mapped_column(String(255))
    region: Mapped[str | None] = mapped_column(String(16), nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class PurchaseLedger(Base):
    __tablename__ = "purchase_ledger"
    provider_purchase_id: Mapped[str] = mapped_column(String(255), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    provider: Mapped[str] = mapped_column(String(32))
    product_id: Mapped[str] = mapped_column(String(128))
    status: Mapped[str] = mapped_column(String(32))
    purchase_metadata: Mapped[dict] = mapped_column("metadata", JSON, default=dict)


class MutationLedger(Base):
    __tablename__ = "mutation_ledger"
    id: Mapped[str] = mapped_column(String(255), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    action: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
