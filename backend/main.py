from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import requests

app = FastAPI()

# Allow requests from Flutter Web or any frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # You can restrict this to ["http://localhost:xxxx"] for security
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class TaskRequest(BaseModel):
    task: str

@app.get("/")
def read_root():
    return {"message": "Welcome to NeuroNudge API with Ollama"}

@app.post("/breakdown/")
def breakdown(data: TaskRequest):
    prompt = f"Break this task down into ADHD-friendly micro steps: {data.task}"

    response = requests.post("http://localhost:11434/api/generate", json={
        "model": "gemma:2b",
        "prompt": prompt,
        "stream": False
    })

    output = response.json().get("response", "Something went wrong.")
    return {"steps": output}
