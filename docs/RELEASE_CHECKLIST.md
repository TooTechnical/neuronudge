# NeuroNudge release checklist

No item in this file authorizes deployment or store publication.

## Required before an Android release candidate

- [ ] Register and confirm the final `com.neuronudge.frontend` Android app in
      the production Firebase project.
- [ ] Download the matching `google-services.json` through a secure channel.
- [ ] Create an upload keystore and local `android/key.properties`; never commit
      either file.
- [ ] Configure the production API URL with
      `--dart-define=AI_BASE_URL=https://...`.
- [ ] Configure backend Application Default Credentials, exact allowed origins,
      exact allowed hosts, and `APP_ENV=production`.
- [ ] Host the reviewed privacy notice at a stable public URL and add a support
      email.
- [ ] Complete Google Play Data safety and content declarations from the final
      build, not assumptions from this checklist.
- [ ] Replace provisional launcher artwork and capture current screenshots.
- [ ] Run accessibility checks with large text and screen readers.
- [ ] Run the full CI suite and test account deletion on a Firebase test user.
- [ ] Build a signed App Bundle and verify its application ID, version, and
      signing certificate before upload.

## Explicitly out of scope until approved

- Production deployment
- Uploading an App Bundle to Google Play
- Creating subscriptions or charging users
- Publishing store listings
