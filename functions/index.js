const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

admin.initializeApp();

exports.sendCaregiverNotification = onDocumentCreated(
  "caregiverInboxes/{caregiverUid}/notifications/{notificationId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const {caregiverUid, notificationId} = event.params;
    const notification = snapshot.data();
    const caregiverDoc = await admin
      .firestore()
      .collection("users")
      .doc(caregiverUid)
      .get();

    const token = caregiverDoc.get("fcmToken");
    if (!token) {
      logger.warn("Caregiver has no FCM token", {caregiverUid, notificationId});
      await snapshot.ref.set(
        {
          delivered: false,
          deliveryError: "missing-fcm-token",
          deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return;
    }

    const title = notification.title || "Missed Medication Alert";
    const body =
      notification.body ||
      `${notification.patientName || "Patient"} missed a scheduled medication.`;

    const response = await admin.messaging().send({
      token,
      notification: {title, body},
      data: {
        notificationId,
        caregiverUid,
        type: String(notification.type || "missedDose"),
        patientId: String(notification.patientId || ""),
        patientName: String(notification.patientName || ""),
        medicationName: String(notification.medicationName || ""),
        language: String(notification.language || "en"),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "med360_caregiver_alerts",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    await snapshot.ref.set(
      {
        delivered: true,
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        messageId: response,
      },
      {merge: true},
    );
  },
);

exports.autoMissPatientDose = onDocumentCreated(
  {
    document: "patientDoses/{doseId}",
    timeoutSeconds: 540,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const dose = snapshot.data();
    if (!dose || dose.status !== "pending") return;

    const scheduledAt = dose.scheduledAt && dose.scheduledAt.toDate ?
      dose.scheduledAt.toDate() :
      null;
    if (!scheduledAt) {
      logger.warn("Dose missing scheduledAt", {doseId: event.params.doseId});
      return;
    }

    const missAt = new Date(scheduledAt.getTime() + 5 * 60 * 1000);
    const delayMs = missAt.getTime() - Date.now();
    if (delayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }

    const doseRef = snapshot.ref;
    const latest = await doseRef.get();
    if (!latest.exists) return;

    const latestDose = latest.data();
    if (!latestDose || latestDose.status !== "pending") return;

    const caregiverIds = Array.isArray(latestDose.caregiverIds) ?
      latestDose.caregiverIds :
      [];
    const shouldNotify =
      latestDose.caregiverAlertsEnabled === true && caregiverIds.length > 0;
    const now = new Date();

    await doseRef.set(
      {
        status: "missed",
        confirmedAt: now.toISOString(),
        caregiverNotified: shouldNotify,
        secondReminderSent: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    if (!shouldNotify) return;

    const batch = admin.firestore().batch();
    for (const caregiverUid of caregiverIds) {
      const notificationId = `MISS-${latestDose.id}-${caregiverUid}`;
      const payload = {
        id: notificationId,
        caregiverId: caregiverUid,
        patientId: String(latestDose.patientId || ""),
        patientUid: String(latestDose.ownerUid || ""),
        patientName: String(latestDose.patientName || "Patient"),
        medicationId: String(latestDose.medicationId || ""),
        medicationName: String(latestDose.medicationName || "medication"),
        missedAt: now.toISOString(),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        channel: "both",
        acknowledged: false,
        title: latestDose.language === "ar" ?
          "Missed Medication Alert" :
          "Missed Medication Alert",
        body: latestDose.language === "ar" ?
          `${latestDose.patientName || "Patient"} missed ${latestDose.medicationName || "a scheduled medication"}.` :
          `${latestDose.patientName || "Patient"} missed ${latestDose.medicationName || "a scheduled medication"}.`,
        language: String(latestDose.language || "en"),
        type: "missedDose",
        delivered: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      const inboxRef = admin
        .firestore()
        .collection("caregiverInboxes")
        .doc(caregiverUid)
        .collection("notifications")
        .doc(notificationId);
      batch.set(inboxRef, payload, {merge: true});

      if (latestDose.ownerUid) {
        const patientAlertRef = admin
          .firestore()
          .collection("patients")
          .doc(String(latestDose.ownerUid))
          .collection("caregiverNotifications")
          .doc(notificationId);
        batch.set(patientAlertRef, payload, {merge: true});
      }
    }

    await batch.commit();
  },
);
