"""Create the authoritative monetization and sync tables."""
from alembic import op
import sqlalchemy as sa

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table("accounts", sa.Column("id", sa.String(36), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False), sa.Column("server_revision", sa.Integer(), nullable=False, server_default="0"), sa.Column("verified", sa.Boolean(), nullable=False, server_default=sa.text("false")), sa.Column("disabled", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    op.create_table("sessions", sa.Column("id", sa.String(36), primary_key=True), sa.Column("account_id", sa.String(36), sa.ForeignKey("accounts.id"), nullable=False), sa.Column("refresh_hash", sa.String(128), nullable=False, unique=True), sa.Column("family_id", sa.String(36), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False), sa.Column("revoked_at", sa.DateTime(timezone=True)), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_table("audit_log", sa.Column("id", sa.String(36), primary_key=True), sa.Column("account_id", sa.String(36), sa.ForeignKey("accounts.id")), sa.Column("event", sa.String(80), nullable=False), sa.Column("request_id", sa.String(64), nullable=False), sa.Column("ip_hash", sa.String(128)), sa.Column("metadata", sa.JSON(), nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_table("rate_limit_events", sa.Column("id", sa.String(36), primary_key=True), sa.Column("key_hash", sa.String(128), nullable=False), sa.Column("route", sa.String(128), nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_table("provider_identities", sa.Column("id", sa.String(36), primary_key=True), sa.Column("account_id", sa.String(36), sa.ForeignKey("accounts.id"), nullable=False), sa.Column("provider", sa.String(32), nullable=False), sa.Column("provider_user_id", sa.String(255), nullable=False), sa.UniqueConstraint("provider", "provider_user_id"))
    op.create_table("entitlements", sa.Column("id", sa.String(36), primary_key=True), sa.Column("account_id", sa.String(36), sa.ForeignKey("accounts.id"), nullable=False), sa.Column("entitlement_id", sa.String(128), nullable=False), sa.Column("active", sa.Boolean(), nullable=False), sa.Column("provider", sa.String(32), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True)), sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False), sa.UniqueConstraint("account_id", "entitlement_id"))
    op.create_table("provider_events", sa.Column("provider_event_id", sa.String(255), primary_key=True), sa.Column("provider", sa.String(32), nullable=False), sa.Column("event_type", sa.String(128), nullable=False), sa.Column("payload", sa.JSON(), nullable=False), sa.Column("processed", sa.Boolean(), nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_table("products", sa.Column("id", sa.String(128), primary_key=True), sa.Column("kind", sa.String(32), nullable=False), sa.Column("active", sa.Boolean(), nullable=False))
    op.create_table("price_variants", sa.Column("id", sa.String(128), primary_key=True), sa.Column("product_id", sa.String(128), sa.ForeignKey("products.id"), nullable=False), sa.Column("provider", sa.String(32), nullable=False), sa.Column("provider_price_id", sa.String(255), nullable=False), sa.Column("region", sa.String(16)), sa.Column("active", sa.Boolean(), nullable=False))
    op.create_table("purchase_ledger", sa.Column("provider_purchase_id", sa.String(255), primary_key=True), sa.Column("account_id", sa.String(36), sa.ForeignKey("accounts.id"), nullable=False), sa.Column("provider", sa.String(32), nullable=False), sa.Column("product_id", sa.String(128), nullable=False), sa.Column("status", sa.String(32), nullable=False), sa.Column("metadata", sa.JSON(), nullable=False))
    op.create_table("mutation_ledger", sa.Column("id", sa.String(255), primary_key=True), sa.Column("account_id", sa.String(36), sa.ForeignKey("accounts.id"), nullable=False), sa.Column("action", sa.String(64), nullable=False), sa.Column("payload", sa.JSON(), nullable=False), sa.Column("status", sa.String(32), nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))

def downgrade() -> None:
    for table in ["mutation_ledger", "purchase_ledger", "price_variants", "products", "provider_events", "entitlements", "provider_identities", "accounts"]:
        op.drop_table(table)
