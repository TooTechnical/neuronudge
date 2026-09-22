from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_validator

from backend.auth import AuthenticatedUser, require_user
from backend.config import get_settings

APP_VERSION = "0.2.0"
MAX_TITLE_LENGTH = 160
MAX_DESCRIPTION_LENGTH = 4000


settings = get_settings()
app = FastAPI(
    title="NeuroNudge API",
    version=APP_VERSION,
    description="Task-planning API for the NeuroNudge productivity application.",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
)

if settings.allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins),
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    )

if settings.allowed_hosts:
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=list(settings.allowed_hosts))


class ProfileContext(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preferredNudgeStyle: str | None = None
    biggestBlocker: str | None = None
    neuroType: str | None = None


class PlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=MAX_TITLE_LENGTH)
    description: str = Field(default="", max_length=MAX_DESCRIPTION_LENGTH)
    profile: ProfileContext = Field(default_factory=ProfileContext)

    @field_validator("title", "description")
    @classmethod
    def strip_text(cls, value: str) -> str:
        return value.strip()


class PlanResponse(BaseModel):
    steps: list[str]
    timeboxMinutes: int = Field(ge=5, le=90)
    tone: str


class ProfileSubmission(BaseModel):
    model_config = ConfigDict(extra="ignore")

    uid: str = Field(min_length=1, max_length=128)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "neuronudge-api",
        "version": APP_VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/profile")
def submit_profile(
    payload: ProfileSubmission,
    user: AuthenticatedUser = Depends(require_user),
) -> dict[str, bool]:
    if payload.uid != user.uid:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Profile user mismatch")
    # Do not log names, email addresses, diagnoses, biographies, or raw tokens.
    # Profile persistence will be added behind verified Firebase identity.
    return {"ok": True}


def infer_domain_steps(title: str, description: str) -> list[str]:
    text = f"{title} {description}".lower()

    if any(k in text for k in ["clean", "tidy", "room", "kitchen", "bedroom", "space"]):
        return [
            "Set a five-minute timer and remove visible rubbish",
            "Clear one high-impact surface",
            "Collect loose items into one container",
            "Put away ten items",
            "Wipe or sweep the most visible area",
        ]

    if any(k in text for k in ["essay", "project", "report", "assignment", "module", "code", "write", "deck", "slides"]):
        return [
            "Open the working file and write a three-bullet plan",
            "Complete the smallest useful piece",
            "Save a checkpoint",
            "Complete the next small piece",
            "Write down the next action before stopping",
        ]

    if any(k in text for k in ["read", "chapter", "book", "paper", "article"]):
        return [
            "Choose the exact pages or section",
            "Read for fifteen minutes and mark three ideas",
            "Write a two-sentence summary",
            "Record one follow-up question",
        ]

    return [
        "Write the smallest next action in one sentence",
        "Work on it for five minutes",
        "Do a ten-minute focused push",
        "Record what changed and the next action",
    ]


def choose_timebox(profile: ProfileContext, text: str) -> int:
    style = (profile.preferredNudgeStyle or "").lower()
    blocker = (profile.biggestBlocker or "").lower()
    neuro = (profile.neuroType or "").lower()

    if "hyperactive" in neuro:
        return 15
    if "starting" in blocker:
        return 15 if "clean" in text.lower() else 10
    if "drill" in style:
        return 25
    return 25


def choose_tone(profile: ProfileContext) -> str:
    tone = profile.preferredNudgeStyle
    if tone in {"Gentle", "Coach", "DrillSergeant", "Comedian"}:
        return tone
    return "Coach"


@app.post("/plan", response_model=PlanResponse)
def plan(
    request: PlanRequest,
    _user: AuthenticatedUser = Depends(require_user),
) -> PlanResponse:
    steps: list[str] = []
    if request.description:
        raw = [
            item.strip(" -•\t\r\n")
            for item in request.description.replace(" then ", "\n").replace(" and ", "\n").splitlines()
        ]
        raw = [item for item in raw if item]
        if 1 <= len(raw) <= 6:
            steps = raw[:5]

    if not steps:
        steps = infer_domain_steps(request.title, request.description)

    timebox = choose_timebox(request.profile, f"{request.title} {request.description}")
    tone = choose_tone(request.profile)
    steps = steps[:3] if timebox <= 15 else steps[:5]

    return PlanResponse(steps=steps, timeboxMinutes=timebox, tone=tone)
