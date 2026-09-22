from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from firebase_admin import auth as firebase_auth

from backend.config import Settings, get_settings
from backend.main import app
from backend.planner import GeneratedPlan


@pytest.fixture
def client() -> TestClient:
    app.dependency_overrides[get_settings] = lambda: Settings(
        environment="test",
        require_auth=True,
        firebase_project_id="neuronudge-test",
        check_revoked_tokens=True,
        allowed_origins=(),
        allowed_hosts=(),
    )
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def auth_headers() -> dict[str, str]:
    return {"Authorization": "Bearer valid-test-token"}


def test_health_exposes_versioned_service_status(client: TestClient):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "neuronudge-api"
    assert response.json()["timestamp"].endswith("+00:00")


def test_plan_requires_authentication(client: TestClient):
    response = client.post("/plan", json={"title": "Write report"})
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


@patch("backend.auth._verify_token", return_value={"uid": "user-123"})
def test_plan_accepts_verified_firebase_identity(_verify, client: TestClient):
    response = client.post(
        "/plan",
        headers=auth_headers(),
        json={
            "title": "Write quarterly report",
            "profile": {"biggestBlocker": "Starting feels hard"},
        },
    )
    assert response.status_code == 200
    assert response.json()["timeboxMinutes"] == 10
    assert 1 <= len(response.json()["steps"]) <= 3
    assert response.json()["source"] == "fallback"


@patch("backend.main.generate_ai_plan")
@patch("backend.auth._verify_token", return_value={"uid": "user-123"})
def test_plan_returns_validated_ai_result(_verify, generate, client: TestClient):
    generate.return_value = GeneratedPlan(
        steps=["Open the report", "Write one heading", "Add three bullets"],
        timeboxMinutes=15,
        tone="Gentle",
    )

    response = client.post(
        "/plan",
        headers=auth_headers(),
        json={"title": "Write quarterly report"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "steps": ["Open the report", "Write one heading", "Add three bullets"],
        "timeboxMinutes": 15,
        "tone": "Gentle",
        "source": "ai",
    }


@patch("backend.main.generate_ai_plan", return_value=None)
@patch("backend.auth._verify_token", return_value={"uid": "user-123"})
def test_plan_falls_back_when_ai_is_unavailable(_verify, _generate, client: TestClient):
    response = client.post(
        "/plan",
        headers=auth_headers(),
        json={"title": "Clean the kitchen"},
    )

    assert response.status_code == 200
    assert response.json()["source"] == "fallback"
    assert response.json()["steps"][0].startswith("Set a five-minute timer")


@patch("backend.auth._verify_token", side_effect=firebase_auth.InvalidIdTokenError("invalid"))
def test_plan_rejects_invalid_firebase_token(_verify, client: TestClient):
    response = client.post("/plan", headers=auth_headers(), json={"title": "Write report"})
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid or expired authentication token"


@patch("backend.auth._verify_token", return_value={"uid": "authenticated-user"})
def test_profile_cannot_write_another_users_profile(_verify, client: TestClient):
    response = client.post(
        "/profile",
        headers=auth_headers(),
        json={"uid": "different-user"},
    )
    assert response.status_code == 403


def test_local_preview_accepts_emulator_profile_uid():
    app.dependency_overrides[get_settings] = lambda: Settings(
        environment="development",
        require_auth=False,
        firebase_project_id="demo-neuronudge",
        check_revoked_tokens=False,
        allowed_origins=(),
        allowed_hosts=(),
    )
    try:
        with TestClient(app) as preview_client:
            response = preview_client.post(
                "/profile",
                json={"uid": "firebase-emulator-user"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_production_settings_reject_disabled_authentication():
    settings = Settings(
        environment="production",
        require_auth=False,
        firebase_project_id="project-id",
        check_revoked_tokens=True,
        allowed_origins=("https://app.example.com",),
        allowed_hosts=("api.example.com",),
    )
    with pytest.raises(RuntimeError, match="cannot be disabled"):
        settings.validate()
