# NeuroNudge Privacy Notice

Last updated: 22 September 2026

NeuroNudge is designed to minimize data collection. This notice describes the
current pre-release application and must be reviewed again before a public
store launch.

## Data the app handles

- Firebase Authentication handles sign-in identity such as user ID, email, and
  display name.
- Profile preferences, tasks, schedules, activation check-ins, and focus
  history are stored on the user's device using Hive.
- When AI planning is requested, the selected task title, description, and the
  limited profile context required to personalize the plan are sent to the
  NeuroNudge API over HTTPS. The API authenticates the request using a Firebase
  ID token and does not persist the submitted profile or task content. When the
  optional AI provider is enabled, that task context is sent to OpenAI to
  generate the plan; NeuroNudge requests that the response not be stored by the
  provider. If AI is unavailable, planning stays within the NeuroNudge API and
  uses a built-in fallback.
- Infrastructure providers may retain short-lived operational and security logs
  under their own policies.

NeuroNudge does not sell personal data and does not include advertising SDKs.

## Control and deletion

Users can delete their NeuroNudge account and all locally stored NeuroNudge
data from Settings. Firebase may require a recent sign-in before account
deletion. Uninstalling the app also removes its local application data under
the operating system's normal behavior.

## Security

Production API calls require verified Firebase identity tokens. Server
credentials are not embedded in the application. Release builds require HTTPS.

## Children and health information

NeuroNudge is a productivity tool, not medical advice, diagnosis, or treatment.
The current release is not directed to children under 13. Users should avoid
entering sensitive information that is unnecessary for task support.

## Changes and contact

Material changes will update the date above. Until a dedicated support address
is established, privacy questions can be submitted through the repository's
GitHub issue tracker. A public support email and hosted privacy-policy URL are
required before store submission.
