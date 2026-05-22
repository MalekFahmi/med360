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
