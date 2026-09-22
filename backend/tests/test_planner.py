from types import SimpleNamespace
from unittest.mock import Mock, patch

from backend.config import Settings
from backend.planner import GeneratedPlan, generate_ai_plan


def settings(*, enabled: bool = True) -> Settings:
    return Settings(
        environment="test",
        require_auth=True,
        firebase_project_id="neuronudge-test",
        check_revoked_tokens=True,
        allowed_origins=(),
        allowed_hosts=(),
        openai_api_key="test-key" if enabled else None,
        openai_model="test-model" if enabled else None,
        openai_timeout_seconds=3,
    )


def planner_kwargs() -> dict[str, object]:
    return {
        "title": "Write report",
        "description": "Draft the findings",
        "preferred_nudge_style": "Gentle",
        "biggest_blocker": "Starting feels hard",
        "neuro_type": "Prefer not to say",
    }


@patch("backend.planner.OpenAI")
def test_ai_planner_returns_schema_validated_output(openai: Mock):
    parsed = GeneratedPlan(
        steps=["Open the document", "Write one heading", "Add three bullets"],
        timeboxMinutes=15,
        tone="Gentle",
    )
    openai.return_value.responses.parse.return_value = SimpleNamespace(output_parsed=parsed)

    result = generate_ai_plan(**planner_kwargs(), settings=settings())

    assert result == parsed
    openai.assert_called_once_with(api_key="test-key", timeout=3, max_retries=1)
    call = openai.return_value.responses.parse.call_args.kwargs
    assert call["model"] == "test-model"
    assert call["text_format"] is GeneratedPlan
    assert call["store"] is False


@patch("backend.planner.OpenAI")
def test_ai_planner_is_not_called_without_configuration(openai: Mock):
    result = generate_ai_plan(**planner_kwargs(), settings=settings(enabled=False))

    assert result is None
    openai.assert_not_called()


@patch("backend.planner.OpenAI", side_effect=RuntimeError("provider unavailable"))
def test_ai_planner_fails_closed_to_fallback(_openai: Mock):
    result = generate_ai_plan(**planner_kwargs(), settings=settings())

    assert result is None
