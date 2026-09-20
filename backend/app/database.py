from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class Base(DeclarativeBase):
    pass


settings = get_settings()
connect_args = (
    {"check_same_thread": False}
    if settings.database_url.startswith("sqlite")
    else {"connect_timeout": 10}
)
engine = create_engine(settings.database_url, pool_pre_ping=True, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    from . import models  # noqa: F401

    Base.metadata.create_all(bind=engine)


def ensure_initial_admin() -> None:
    settings = get_settings()
    if not settings.initial_admin_username or not settings.initial_admin_password:
        return
    if len(settings.initial_admin_password) < 12:
        raise RuntimeError("INITIAL_ADMIN_PASSWORD 至少需要 12 个字符")

    from .models import User
    from .security import hash_password

    with SessionLocal() as db:
        user = db.query(User).filter(User.username == settings.initial_admin_username).one_or_none()
        if user is None:
            user = User(
                username=settings.initial_admin_username,
                password_hash=hash_password(settings.initial_admin_password),
                is_admin=True,
            )
            db.add(user)
        elif not user.is_admin:
            user.is_admin = True
        db.commit()
