from datetime import datetime
from pydantic import BaseModel, Field


class AccountResponse(BaseModel):
    account_id: str
    access_token: str
    refresh_token: str


class OidcExchangeRequest(BaseModel):
    id_token: str = Field(min_length=20, max_length=10000)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=256)


class ProviderLinkRequest(BaseModel):
    provider: str = Field(pattern="^(revenuecat|stripe)$")
    provider_user_id: str = Field(min_length=1, max_length=255)


class EntitlementResponse(BaseModel):
    entitlement_id: str
    active: bool
    provider: str
    expires_at: datetime | None


class ActiveEntitlementItem(BaseModel):
    """One active entitlement in RevenueCat's `active_entitlements` shape."""

    entitlement_id: str
    # Milliseconds since the epoch; null means a lifetime grant. The game's
    # parser treats any past or malformed expiry as lapsed.
    expires_at: int | None = None


class ActiveEntitlementsResponse(BaseModel):
    items: list[ActiveEntitlementItem]


class TransactionItem(BaseModel):
    """One store purchase in RevenueCat's `non_subscriptions` shape.

    The game claims repeatable consumables per transaction, so a device needs
    the transaction list — not just the active entitlements — to grant a pack
    once per purchase.
    """

    product_id: str
    transaction_id: str
    # Milliseconds since the epoch; 0 when the provider gives no date.
    purchased_at: int = 0


class TransactionsResponse(BaseModel):
    items: list[TransactionItem]


class MutationRequest(BaseModel):
    id: str = Field(min_length=1, max_length=255)
    action: str = Field(min_length=1, max_length=64)
    payload: dict = Field(default_factory=dict)


class CheckoutRequest(BaseModel):
    price_variant_id: str = Field(min_length=1)
    distribution: str = Field(pattern="^(web|android)$")
    region: str = Field(min_length=2, max_length=16)
