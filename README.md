# NeuroNudge 

NeuroNudge is an **AI-powered productivity assistant** designed to support individuals with ADHD and those who struggle with procrastination.  
The app transforms overwhelming tasks into **small, achievable steps**, provides **motivational nudges** in different tones (humorous, encouraging, or commanding), and rewards progress with **dopamine-triggering feedback** like streaks, badges, and sounds.


##  Project Status
- **Stage:** Pre-release MVP (not yet deployed)
- **Deployment:** Pending  
- **Focus:** Building out core features and user onboarding  

## Development

The current application version is a pre-release MVP. See
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) before producing an
Android release candidate and [`PRIVACY.md`](PRIVACY.md) for the pre-release
privacy notice.

### Backend

Use Python 3.12 and install `backend/requirements-dev.txt`. Copy
`backend/.env.example` to `backend/.env` for local values; `.env` files and
service-account credentials must never be committed.

The API verifies every protected request with Firebase Admin. Firebase Admin
uses Application Default Credentials. Production must provide credentials via
the hosting platform or `GOOGLE_APPLICATION_CREDENTIALS`, and must set:

- `APP_ENV=production`
- `FIREBASE_PROJECT_ID`
- `ALLOWED_ORIGINS` to the exact web origins allowed to call the API
- `ALLOWED_HOSTS` to the API's exact host names

AI-generated plans are optional. Set both `OPENAI_API_KEY` and `OPENAI_MODEL`
in the backend's secret environment to enable them. The API requests
schema-validated output with provider storage disabled, applies a short timeout,
and falls back to its built-in planner whenever AI is not configured or is
unavailable. Never put the API key in Flutter or commit it to the repository.

Authentication cannot be disabled when `APP_ENV=production`. API documentation
is also disabled in production. Run the backend locally from the repository
root with `uvicorn backend.main:app --reload`.

### Flutter

Release builds require the API URL at build time and reject non-HTTPS values:

```sh
flutter build appbundle --dart-define=AI_BASE_URL=https://api.example.com
```

Firebase client configuration files contain client identifiers, not Admin SDK
credentials. Keep separate Firebase projects/configurations for development and
production. Never put a service-account JSON file in the Flutter application.

### Checks

Pull requests run backend tests, Flutter formatting checks, static analysis,
and Flutter tests. Equivalent local checks are:

```sh
python -m pytest -q backend/tests
cd frontend
flutter analyze
flutter test
```



##  Tech Stack & Programming Languages
NeuroNudge is being developed using:  
- **Flutter (Dart)** – Mobile app frontend (cross-platform for iOS & Android)  
- **Python (FastAPI)** – Backend API services  
- **Firebase Firestore** – Real-time database for storing user data  
- **Firebase Auth** – Authentication (Email & Google Sign-In)  
- **Stripe** – Subscription billing (planned for Premium/Pro tiers)  



##  Features

### Currently Implemented
- User authentication via Firebase (Email & Google Sign-In)  
- Local task creation, task listing, and schedules
- Personalized onboarding and activation preferences
- AI task breakdown with a safe built-in fallback
- Get Me Started micro-missions, Rescue Mode, and Body Double focus sessions
- Realistic-day planning with capacity buffers
- Local behavioral insights, streaks, and progress tracking
- In-app account and local-data deletion controls

### In Development
- Motivational nudges system (humor, drill sergeant, supportive tones)  
- Release signing, hosted privacy/support pages, and store assets

### Planned
- Text-to-Speech nudges  
- Voice input for adding tasks  
- Advanced analytics dashboard  
- Subscription tiers with Stripe

  

##  Roadmap
- [x] Complete onboarding and personalization
- [x] Implement activation and feedback loops
- [ ] Deploy MVP to app stores  
- [ ] Expand into premium subscription features  


##  About the Project
This project is an exploration of how **technology, AI, and behavioral design** can come together to improve focus and motivation. It represents ongoing work in **full-stack development (Flutter + Python)**, API design, and mobile deployment.  



##  About Me
I am a **Full Stack Developer** with experience in **web and mobile application development**.  
NeuroNudge is part of my professional portfolio and demonstrates my ability to:  
- Build mobile applications with Flutter  
- Develop backend services with Python (FastAPI)  
- Integrate Firebase for authentication and real-time data storage  
- Work with subscription systems (Stripe)  
- Apply software development practices to create real-world solutions  

##  Note to Employers
I am actively developing NeuroNudge as part of my **portfolio of full-stack projects**.  
While the app is still in **mid-development**, it demonstrates my ability to:  
- Build cross-platform mobile applications with **Flutter (Dart)**  
- Develop backend services and APIs with **Python (FastAPI)**  
- Work with **Firebase** for authentication and real-time databases  
- Implement **subscription and payment systems** (Stripe)  
- Apply software engineering practices to deliver scalable, real-world solutions  

NeuroNudge is more than a coding exercise — it reflects my ability to take an idea from concept to execution, combining **technical skills, creativity, and problem-solving**. I am excited to continue growing as a developer and bring these skills into a professional role.  
