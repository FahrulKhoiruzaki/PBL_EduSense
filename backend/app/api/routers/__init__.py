from fastapi import APIRouter

from . import admin, admin_cms, admin_school_info, auth, guru, guru_face, ortu, public

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(public.router)
api_router.include_router(guru.router)
api_router.include_router(guru_face.router)
api_router.include_router(ortu.router)
api_router.include_router(admin.router)
api_router.include_router(admin_cms.router)
api_router.include_router(admin_school_info.router)
