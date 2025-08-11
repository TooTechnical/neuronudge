#!/bin/bash

# Run backend (FastAPI with Uvicorn)
echo "Starting backend..."
uvicorn main:app --reload &
BACKEND_PID=$!

# Wait a bit to ensure backend is ready
sleep 3

# Run frontend (Flutter)
echo "Launching Flutter app..."

flutter run -d chrome

# Once frontend exits, stop backend
kill $BACKEND_PID
