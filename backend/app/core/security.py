from fastapi import Header, HTTPException, status

from app.core.config import get_settings


async def verify_shared_secret(authorization: str | None = Header(default=None)) -> None:
    """Optional bearer-token gate. No-op if APP_SHARED_SECRET is unset."""
    settings = get_settings()
    if not settings.app_shared_secret:
        return

    expected = f"Bearer {settings.app_shared_secret}"
    if authorization != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )
