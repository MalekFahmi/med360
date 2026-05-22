# MED360

MED360 is a standalone Flutter medication adherence app for Arabic-speaking patients. Patients can create their own account, enter medication schedules, receive local reminders, confirm taken or missed doses, review adherence reports, and manage caregiver alerts without relying on an external API.

## Current Scope

- Patient sign up, login, logout, and local session restore.
- Patient-managed medication list with dosage, form, notes, status, reminder type, and multiple reminder times.
- Local notification or alarm scheduling for medication reminders.
- Dose confirmation for taken and missed medication doses.
- Local adherence history and monthly adherence summaries.
- Caregiver management with missed-dose alert permissions.
- Firebase-ready caregiver alert syncing through Firestore/FCM when Firebase config is added.
- Arabic mode, right-to-left layout, large font option, and high contrast setting.
- Offline-first storage using SQLite and shared preferences.

## Updated Functional Requirements

FR1 - Patient Account Creation: The system shall allow a patient to create and manage a local MED360 account.

FR2 - Patient Authentication: The system shall allow registered patients to log in and access their medication data.

FR3 - Medication Management: The system shall allow patients to add, edit, pause, resume, and delete their own medication records, including dosage, form, indication, notes, reminder type, and reminder times.

FR4 - Medication Reminder Generation: The system shall generate local medication reminders based on the patient-entered schedule and notify the patient using notifications or alarms.

FR5 - Dose Confirmation: The system shall allow patients to confirm whether a scheduled dose was taken or missed.

FR6 - Adherence Tracking: The system shall record and store dose confirmations locally over time.

FR7 - Adherence Reporting: The system shall generate monthly medication adherence reports from recorded dose history.

FR8 - Caregiver Notifications: The system shall notify configured caregivers when a scheduled medication dose is missed, if caregiver alerts are enabled by the patient.

FR9 - Caregiver Management: The system shall allow patients to add, remove, and set notification permissions for caregivers.

FR10 - Offline Operation: The system shall keep core medication, reminder, adherence, and caregiver features available without continuous internet access.

## Non-Functional Requirements

- Usability: Simple workflows for users with limited technical experience.
- Accessibility: Arabic language support, RTL layout, clear icons, and large-font support.
- Reliability: Medication and adherence data are stored locally and survive app restarts.
- Performance: Reminder scheduling and screen loading should remain lightweight.
- Maintainability: Providers, models, services, and screens are separated for future extension.

## Running

```bash
flutter pub get
flutter run
```

For real caregiver push notifications across devices, follow [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

## Verification

```bash
flutter analyze
flutter test
```
