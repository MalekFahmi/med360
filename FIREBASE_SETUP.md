# Firebase Setup for Caregiver Notifications

MED360 now contains Firebase-ready code for caregiver alerts:

- Patient profile/device registration: `patients/{patientId}`
- Caregiver records: `patients/{patientId}/caregivers/{caregiverId}`
- Missed-dose alert log: `patients/{patientId}/caregiverNotifications/{notificationId}`
- Caregiver inbox: `caregiverInboxes/{caregiverId}/notifications/{notificationId}`

The app still works offline with SQLite if Firebase is not configured. Firebase is disabled safely until the project config is added.

## Required Firebase Steps

1. Create a Firebase project.
2. Enable Cloud Firestore.
3. Enable Cloud Messaging.
4. Install FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
```

5. Configure this Flutter app:

```bash
flutterfire configure
```

6. Add the generated platform files to the project, especially:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist` if building iOS
- `lib/firebase_options.dart` if you choose to initialize with generated options later

## Important Push Notification Note

A phone cannot directly send an FCM push notification to another phone securely. The patient app writes the missed-dose alert to Firestore. To make the caregiver receive a real push notification, add a Firebase Cloud Function that listens to `caregiverInboxes/{caregiverId}/notifications/{notificationId}` and sends FCM to the caregiver device token.

The current app writes the alert documents that this backend function needs. The remaining Firebase-side requirement is caregiver device registration and a Cloud Function for sending the push.

## Suggested Firestore Rule Shape

Start restrictive. For a graduation demo, you can test with authenticated users, then tighten patient/caregiver ownership before production.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /patients/{patientId}/{document=**} {
      allow read, write: if request.auth != null;
    }

    match /caregiverInboxes/{caregiverId}/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```
