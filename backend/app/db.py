from collections.abc import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from .config import get_settings


class Base(DeclarativeBase):
    pass


def _engine_url(url: str) -> str:
    return url.replace("postgres://", "postgresql+psycopg://", 1).replace(
        "postgresql://", "postgresql+psycopg://", 1
    )


engine = create_engine(_engine_url(get_settings().database_url), pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
