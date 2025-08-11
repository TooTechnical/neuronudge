import os
from openai import OpenAI

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

def get_task_steps(task: str) -> str:
    response = client.chat.completions.create(
        model="gpt-4",
        messages=[
            {"role": "system", "content": "Break big tasks into ADHD-friendly micro-steps."},
            {"role": "user", "content": f"Break this task down: {task}"}
        ]
    )
    return response.choices[0].message.content
