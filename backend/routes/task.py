from fastapi import APIRouter
from backend.models.task_model import TaskRequest
from backend.utils.openai_client import get_task_steps

router = APIRouter()

@router.post("/breakdown/")
def breakdown(data: TaskRequest):
    return {"steps": get_task_steps(data.task)}
