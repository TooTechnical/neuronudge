from typing import List, Optional, Dict, Any
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from datetime import datetime

app = FastAPI(title="NeuroNudge AI Stub", version="0.1.0")

# 🔓 DEV CORS: wide-open for development (lock down in production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        # In production, set to your web/app origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =========================
#        DATA MODELS
# =========================

class Profile(BaseModel):
    uid: Optional[str] = None
    email: Optional[str] = None

    # identity
    name: Optional[str] = None
    pronouns: Optional[str] = None
    age: Optional[int] = None
    role: Optional[str] = None

    # neuro
    neuroType: Optional[str] = None           # e.g., "ADHD - Hyperactive"
    bio: Optional[str] = None                 # <= 500 chars
    strengths: Optional[List[str]] = None
    weaknesses: Optional[List[str]] = None

    # schedule
    workStart: Optional[str] = None           # "HH:MM"
    workEnd: Optional[str] = None             # "HH:MM"
    workDays: Optional[List[int]] = None      # 1..7 (Mon..Sun)
    allowWindows: Optional[Dict[str, bool]] = None  # {'before':bool,'during':bool,'after':bool}
    dailyTaskTarget: Optional[int] = None

    # goals & nudges
    goals: Optional[str] = None
    biggestBlocker: Optional[str] = None
    preferredNudgeStyle: Optional[str] = None # 'Gentle'|'Coach'|'DrillSergeant'|'Comedian'
    allowSounds: Optional[bool] = None

    # audit (from client)
    createdAt: Optional[Any] = None
    updatedAt: Optional[Any] = None


class PlanRequest(BaseModel):
    title: str
    description: Optional[str] = ""
    profile: Dict[str, Any] = Field(default_factory=dict)


class PlanResponse(BaseModel):
    steps: List[str]
    timeboxMinutes: int
    tone: str  # 'Coach' | 'DrillSergeant' | 'Gentle' | 'Comedian'


# =========================
#    IN-MEMORY PROFILE DB
# =========================
# (Dev only. Replace with a real database later.)
PROFILES: Dict[str, Profile] = {}


# =========================
#       HELPERS/LOGIC
# =========================

def _pick_tone(profile: Dict[str, Any]) -> str:
    """Choose the coaching tone from profile, with a sensible default."""
    pref = (profile.get("preferredNudgeStyle") or "").strip()
    if pref:
        return pref.replace(" ", "")  # normalize "Drill Sergeant" -> "DrillSergeant"
    neuro = (profile.get("neuroType") or "").lower()
    if "hyper" in neuro or ("adhd" in neuro and "high" in neuro):
        return "DrillSergeant"
    return "Coach"


def _plan_by_keywords(title: str, description: str, profile: Dict[str, Any]) -> PlanResponse:
    """Simple heuristic planner until your real model is plugged in."""
    text = f"{title} {description}".lower()

    is_clean = any(w in text for w in [
        "clean", "tidy", "organize", "bedroom", "room", "kitchen", "desk", "space"
    ])
    is_project = any(w in text for w in [
        "project", "build", "code", "write", "essay", "report", "website", "deploy", "module", "task"
    ])
    is_reading = any(w in text for w in [
        "read", "book", "chapter", "study", "revise", "revision"
    ])

    tone = _pick_tone(profile)
    weaknesses = [w.lower() for w in (profile.get("weaknesses") or [])]

    # Defaults
    minutes = 15
    steps: List[str] = [
        "Define the smallest first step (write it down)",
        "Work without perfection for 15 minutes",
        "Stop, review, and write the next tiny step",
    ]

    if is_clean:
        minutes = 30 if "personal space" in text else 10
        steps = [
            f"Set a timer for {minutes} minutes",
            "Pick ONE zone (desk/surface/floor)",
            "Remove trash & laundry first",
            "Group items: keep / bin / move",
            "Reset the zone; stop when timer ends",
        ]
    elif is_project:
        minutes = 60
        steps = [
            "Open the exact file/doc you need",
            "Write a 3-line session plan",
            "Do the first subtask for 25 minutes",
            "Short break (5 minutes), then continue",
            "Save/commit and write a 1-line summary",
        ]
    elif is_reading:
        minutes = 30
        steps = [
            "Pick a section that fits 30 minutes",
            "Underline 3 key ideas while reading",
            "Write 3 bullet takeaways at the end",
            "Stop when the timer ends",
        ]

    # Adjust for weaknesses
    if "time estimation" in weaknesses and minutes > 20:
        minutes = max(25, minutes - 5)
    if "starting" in weaknesses and minutes > 10:
        steps.insert(0, "2-minute ignition: open materials and type the task name")

    return PlanResponse(steps=steps, timeboxMinutes=minutes, tone=tone)


# =========================
#          ROUTES
# =========================

@app.get("/")
def root():
    return {"ok": True, "service": "NeuroNudge AI Stub", "now": datetime.utcnow().isoformat() + "Z"}


@app.get("/api/health")
def health():
    return {"ok": True}


@app.post("/api/profile")
def post_profile(profile: Profile):
    """
    Receives a user profile from the app (onboarding).
    In dev, we store it in-memory keyed by uid.
    """
    uid = profile.uid or "anon"
    PROFILES[uid] = profile
    return {"ok": True, "stored": bool(uid)}


@app.post("/api/plan", response_model=PlanResponse)
def post_plan(req: PlanRequest):
    """
    Returns steps, timeboxMinutes, and tone for the given task title/description,
    using heuristics informed by the supplied profile.
    Replace this with your real model when ready.
    """
    return _plan_by_keywords(req.title, req.description or "", req.profile)
