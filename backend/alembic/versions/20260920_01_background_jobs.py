"""Add administrator flag and background job runs.

Revision ID: 20260920_01
Revises:
"""
from alembic import op
import sqlalchemy as sa


revision = "20260920_01"
down_revision = None
branch_labels = None
depends_on = None


def _index_names(inspector: sa.Inspector, table: str) -> set[str]:
    return {item["name"] for item in inspector.get_indexes(table)}


def upgrade() -> None:
    bind = op.get_bind()
    from app.database import Base
    from app import models  # noqa: F401

    # This project predates Alembic. create_all bootstraps a new database while
    # the conditional ALTER below safely adopts existing installations.
    Base.metadata.create_all(bind=bind)
    inspector = sa.inspect(bind)
    user_columns = {item["name"] for item in inspector.get_columns("users")}
    if "is_admin" not in user_columns:
        op.add_column(
            "users",
            sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.false()),
        )
    inspector = sa.inspect(bind)
    if "ix_users_is_admin" not in _index_names(inspector, "users"):
        op.create_index("ix_users_is_admin", "users", ["is_admin"], unique=False)


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "background_job_runs" in inspector.get_table_names():
        op.drop_table("background_job_runs")
    inspector = sa.inspect(bind)
    if "users" in inspector.get_table_names():
        indexes = _index_names(inspector, "users")
        if "ix_users_is_admin" in indexes:
            op.drop_index("ix_users_is_admin", table_name="users")
        columns = {item["name"] for item in inspector.get_columns("users")}
        if "is_admin" in columns:
            op.drop_column("users", "is_admin")
