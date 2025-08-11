from pydantic import BaseModel

class TaskRequest(BaseModel):
    task: str
