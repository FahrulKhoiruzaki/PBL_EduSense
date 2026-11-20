from pydantic import BaseModel, Field


class LoginIn(BaseModel):
    email: str = Field(min_length=1, max_length=254)
    password: str = Field(min_length=1, max_length=256)


class ForgotPasswordIn(BaseModel):
    email: str = Field(min_length=1, max_length=254)


class ChangePasswordIn(BaseModel):
    new_password: str = Field(min_length=1, max_length=256)


class UserOut(BaseModel):
    id: int
    email: str
    nama: str
    role: str
    must_change_password: bool


class GuruOut(BaseModel):
    nip: str | None
    wali_kelas: list[str]
    mapel: list[str]


class PengaturanOut(BaseModel):
    batas_jam_terlambat: str | None


class SessionOut(BaseModel):
    user: UserOut
    guru: GuruOut | None = None
    pengaturan: PengaturanOut


class LoginOut(SessionOut):
    token: str
