from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    ForeignKeyConstraint,
    Identity,
    Integer,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import DateTime

from .base import Base, UserRole, pg_enum


def _created() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


class User(Base):
    __tablename__ = "users"
    __table_args__ = (UniqueConstraint("id", "role"),)

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    email: Mapped[str] = mapped_column(Text)
    password_hash: Mapped[str] = mapped_column(Text)
    role: Mapped[UserRole] = mapped_column(pg_enum(UserRole, "user_role"))
    is_active: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    must_change_password: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _created()
    token_version: Mapped[int] = mapped_column(Integer, server_default=text("0"))

    admin_profile: Mapped["Admin | None"] = relationship(back_populates="user", uselist=False)
    guru_profile: Mapped["Guru | None"] = relationship(back_populates="user", uselist=False)
    ortu_profile: Mapped["OrangTua | None"] = relationship(back_populates="user", uselist=False)


class Admin(Base):
    __tablename__ = "admin"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "role"], ["users.id", "users.role"], ondelete="CASCADE"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, unique=True)
    role: Mapped[UserRole] = mapped_column(
        pg_enum(UserRole, "user_role"), server_default=text("'admin'")
    )
    nama: Mapped[str] = mapped_column(Text)

    user: Mapped[User] = relationship(back_populates="admin_profile")


class Guru(Base):
    __tablename__ = "guru"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "role"], ["users.id", "users.role"], ondelete="CASCADE"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, unique=True)
    role: Mapped[UserRole] = mapped_column(
        pg_enum(UserRole, "user_role"), server_default=text("'guru'")
    )
    nip: Mapped[str | None] = mapped_column(Text)
    nama: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _created()
    jabatan: Mapped[str | None] = mapped_column(Text)
    foto_url: Mapped[str | None] = mapped_column(Text)
    tampil_publik: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))

    user: Mapped[User] = relationship(back_populates="guru_profile")


class OrangTua(Base):
    __tablename__ = "orang_tua"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "role"], ["users.id", "users.role"], ondelete="CASCADE"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    user_id: Mapped[int] = mapped_column(BigInteger, unique=True)
    role: Mapped[UserRole] = mapped_column(
        pg_enum(UserRole, "user_role"), server_default=text("'ortu'")
    )
    nama_lengkap: Mapped[str] = mapped_column(Text)
    no_hp: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _created()

    user: Mapped[User] = relationship(back_populates="ortu_profile")
