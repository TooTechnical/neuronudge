from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import firebase_admin
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as firebase_auth
from google.auth.exceptions import GoogleAuthError

from backend.config import Settings, get_settings

bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthenticatedUser:
    uid: str
    claims: dict[str, Any]


def _firebase_app(settings: Settings) -> firebase_admin.App:
    try:
        return firebase_admin.get_app()
    except ValueError:
        options = {"projectId": settings.firebase_project_id} if settings.firebase_project_id else None
        # Uses Application Default Credentials. In production, provide credentials
        # through the hosting platform or GOOGLE_APPLICATION_CREDENTIALS, never Git.
        return firebase_admin.initialize_app(options=options)


def _verify_token(token: str, settings: Settings) -> dict[str, Any]:
    return firebase_auth.verify_id_token(
        token,
        app=_firebase_app(settings),
        check_revoked=settings.check_revoked_tokens,
    )


def require_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    settings: Settings = Depends(get_settings),
) -> AuthenticatedUser:
    if not settings.require_auth:
        return AuthenticatedUser(uid="local-preview", claims={"local_preview": True})

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        claims = _verify_token(credentials.credentials, settings)
        uid = claims.get("uid") or claims.get("sub")
        if not isinstance(uid, str) or not uid:
            raise ValueError("Token has no user identifier")
    except firebase_auth.RevokedIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication token has been revoked",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except (firebase_auth.InvalidIdTokenError, firebase_auth.ExpiredIdTokenError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except (firebase_admin.exceptions.FirebaseError, GoogleAuthError):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service unavailable",
        ) from None

    return AuthenticatedUser(uid=uid, claims=claims)
