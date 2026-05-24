# MED360 External Worker

This worker replaces Firebase Cloud Functions when the Firebase project cannot use Blaze.

It runs outside Firebase, checks Firestore every minute, marks overdue pending doses as missed after 5 minutes, writes caregiver inbox notifications, and sends caregiver OS push notifications through FCM.

## Required Firebase Setup

Create a Firebase service account:

1. Open Firebase Console.
2. Project settings.
3. Service accounts.
4. Generate new private key.

Do not commit that JSON file.

## Local Run

```bash
cd external-worker
npm install
set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json
npm start
```

PowerShell base64 option:

```powershell
$json = Get-Content C:\path\to\service-account.json -Raw
$env:FIREBASE_SERVICE_ACCOUNT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
npm start
```

## Render/Railway/Fly.io

Use these settings:

- Build command: `npm install`
- Start command: `npm start`
- Root directory: `external-worker`

Environment variables:

- `FIREBASE_SERVICE_ACCOUNT_BASE64`: base64 service account JSON
- `POLL_INTERVAL_SECONDS`: `60`
- `AUTO_MISS_DELAY_MINUTES`: `5`
- `PORT`: host-provided, or `8080`

## Health Check

The worker exposes:

```text
GET /health
```

It returns the last successful poll timestamp, processed counts, and any last error.

## Important

Keep exactly one worker instance running. Multiple instances are mostly safe because updates are transactional and notification IDs are deterministic, but one instance avoids unnecessary duplicate work.
