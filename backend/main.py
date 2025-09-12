# backend/main.py
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI()

# Allow Flutter web to call the API locally (relax for dev; tighten for prod)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        # TODO: lock this down for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------- Models ----------
class PlanRequest(BaseModel):
    title: str
    description: Optional[str] = ""
    profile: Dict[str, Any] = Field(default_factory=dict)

class PlanResponse(BaseModel):
    steps: List[str]
    timeboxMinutes: int
    tone: str

# ---------- Health ----------
@app.get("/health")
def health():
    return {"ok": True, "ts": datetime.utcnow().isoformat()}

# ---------- Profile (optional “learning” endpoint) ----------
@app.post("/profile")
def profile(payload: Dict[str, Any], request: Request):
    # You can persist this later; for now just log it so we know calls arrive
    print(
        f"[profile] from {request.client.host} "
        f"uid={payload.get('uid')} "
        f"name={payload.get('name') or payload.get('email')}"
    )
    return {"ok": True}

# ---------- Heuristics ----------
def infer_domain_steps(title: str, description: str) -> List[str]:
    text = f"{title} {description}".lower()

    # Cleaning-style tasks
    if any(k in text for k in ["clean", "tidy", "room", "kitchen", "bedroom", "space"]):
        return [
            "Set a 5-minute timer and bag visible trash",
            "Make the bed or clear desk surface",
            "Collect loose items into one basket",
            "Put away 10 things (count out loud)",
            "Quick wipe/sweep the highest-impact spots",
        ]

    # Writing/coding/study
    if any(k in text for k in ["essay", "project", "report", "assignment", "module", "code", "write", "deck", "slides"]):
        return [
            "Open file & write a 3-bullet plan",
            "Do the first micro-task (≤10 min)",
            "Commit/save a checkpoint",
            "Do the second micro-task (≤10 min)",
            "Write the next-step note at the top",
        ]

    # Reading
    if any(k in text for k in ["read", "chapter", "book", "paper", "article"]):
        return [
            "Pick exact pages/section (e.g., 8–12)",
            "Read 15 min; mark 🔖 3 ideas",
            "Write a two-sentence summary",
            "Create one follow-up question",
        ]

    # Generic default
    return [
        "Write the smallest next action in 1 line",
        "Work 5 minutes to get momentum",
        "Do a 10-minute push on the core bit",
        "Wrap: log what moved & next step",
    ]

def choose_timebox(profile: Dict[str, Any], text: str) -> int:
    style = (profile.get("preferredNudgeStyle") or "").lower()
    blocker = (profile.get("biggestBlocker") or "").lower()
    neuro = (profile.get("neuroType") or "").lower()

    if "hyperactive" in neuro:
        return 15
    if "starting" in blocker:
        return 10 if "clean" not in text.lower() else 15
    if "drill" in style:
        return 25
    return 25

def choose_tone(profile: Dict[str, Any]) -> str:
    tone = profile.get("preferredNudgeStyle")
    if tone in {"Gentle", "Coach", "DrillSergeant", "Comedian"}:
        return tone
    return "Coach"

# ---------- Planner ----------
@app.post("/plan", response_model=PlanResponse)
def plan(req: PlanRequest, request: Request):
    print(f"[plan] from {request.client.host} title={req.title!r}")

    # 1) try to split user-provided description into steps
    steps: List[str] = []
    desc = (req.description or "").strip()
    if desc:
        raw = [
            s.strip(" -•\t\r\n")
            for s in desc.replace(" then ", "\n").replace(" and ", "\n").splitlines()
        ]
        raw = [r for r in raw if r]
        if 1 <= len(raw) <= 6:
            steps = raw[:5]

    # 2) otherwise, infer steps from task domain
    if not steps:
        steps = infer_domain_steps(req.title, req.description or "")

    # 3) choose timebox & tone from profile/task
    tb = choose_timebox(req.profile, f"{req.title} {req.description}")
    tone = choose_tone(req.profile)

    # 4) keep it tight: 3 steps for ≤15 min, else up to 5
    steps = steps[:3] if tb <= 15 else steps[:5]

    return PlanResponse(steps=steps, timeboxMinutes=tb, tone=tone)
