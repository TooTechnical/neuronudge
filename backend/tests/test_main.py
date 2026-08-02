import os

from fastapi.testclient import TestClient

os.environ.setdefault("REQUIRE_AUTH", "true")

from main import app  # noqa: E402

client = TestClient(app)


def test_health_exposes_versioned_service_status():
    response = client.get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["service"] == "neuronudge-api"
    assert payload["version"]
    assert payload["timestamp"].endswith("+00:00")


def test_plan_requires_authentication():
    response = client.post(
        "/plan",
        json={"title": "Write report", "description": "", "profile": {}},
    )

    assert response.status_code == 401


def test_plan_rejects_unknown_fields():
    response = client.post(
        "/plan",
        headers={"Authorization": "Bearer test-token"},
        json={"title": "Write report", "description": "", "profile": {}, "unexpected": True},
    )

    assert response.status_code == 422


def test_plan_returns_small_steps_for_starting_blocker():
    response = client.post(
        "/plan",
        headers={"Authorization": "Bearer test-token"},
        json={
            "title": "Write quarterly report",
            "description": "",
            "profile": {
                "preferredNudgeStyle": "Coach",
                "biggestBlocker": "Starting feels hard",
                "neuroType": "ADHD - Inattentive",
            },
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["timeboxMinutes"] == 10
    assert 1 <= len(payload["steps"]) <= 3
    assert payload["tone"] == "Coach"


def test_profile_does_not_accept_missing_uid():
    response = client.post(
        "/profile",
        headers={"Authorization": "Bearer test-token"},
        json={"email": "private@example.com"},
    )

    assert response.status_code == 422
