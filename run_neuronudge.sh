#!/bin/bash

# Run FastAPI backend in a new Terminal tab
osascript <<EOF
tell application "Terminal"
    do script "cd \"$(pwd)/backend\"; source ../venv/bin/activate; uvicorn main:app --reload --host 0.0.0.0 --port 8000"
end tell
EOF

# Wait a moment to let backend start
sleep 3

# Run Flutter frontend in current tab
cd frontend
flutter run
