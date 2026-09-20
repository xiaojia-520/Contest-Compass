"""Add native client preferences and app releases.

Revision ID: 20260920_02
Revises: 20260920_01
"""
from alembic import op
import sqlalchemy as sa


revision = "20260920_02"
down_revision = "20260920_01"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    from app.database import Base
    from app import models  # noqa: F401

    Base.metadata.create_all(bind=bind)
    inspector = sa.inspect(bind)
    user_columns = {item["name"] for item in inspector.get_columns("users")}
    if "reminders_enabled" not in user_columns:
        op.add_column(
            "users",
            sa.Column("reminders_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        )
    project_columns = {item["name"] for item in inspector.get_columns("projects")}
    if "reminders_enabled" not in project_columns:
        op.add_column(
            "projects",
            sa.Column("reminders_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "app_releases" in inspector.get_table_names():
        op.drop_table("app_releases")
    if "projects" in inspector.get_table_names():
        columns = {item["name"] for item in inspector.get_columns("projects")}
        if "reminders_enabled" in columns:
            op.drop_column("projects", "reminders_enabled")
    if "users" in inspector.get_table_names():
        columns = {item["name"] for item in inspector.get_columns("users")}
        if "reminders_enabled" in columns:
            op.drop_column("users", "reminders_enabled")
