const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

admin.initializeApp();

function normalizePhone(phone) {
  return String(phone || "").replace(/[^0-9]/g, "");
}

exports.createPatientAccountRequest = onDocumentCreated(
  "patientAccountRequests/{requestId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const request = snapshot.data();
    const caregiverUid = String(request.caregiverUid || "");
    const email = String(request.email || "").trim().toLowerCase();
    const password = String(request.password || "");
    const name = String(request.name || "").trim();
    const phone = String(request.phone || "").trim();
    const chronicCondition = request.chronicCondition ?
      String(request.chronicCondition).trim() :
      null;

    try {
      if (!caregiverUid || !email || !password || !name || !phone) {
        throw new Error("missing-required-fields");
      }

      const caregiverDoc = await admin
        .firestore()
        .collection("users")
        .doc(caregiverUid)
        .get();
      const caregiver = caregiverDoc.data();
      if (!caregiver || caregiver.role !== "caregiver") {
        throw new Error("requester-is-not-caregiver");
      }

      const userRecord = await admin.auth().createUser({
        email,
        password,
        displayName: name,
      });
      const patientUid = userRecord.uid;
      const patientId = `PAT-${Date.now()}`;
      const phoneNormalized = normalizePhone(phone);
      const now = admin.firestore.FieldValue.serverTimestamp();
      const db = admin.firestore();
      const batch = db.batch();

      batch.set(db.collection("users").doc(patientUid), {
        uid: patientUid,
        role: "patient",
        patientId,
        name,
        email,
        phone,
        phoneNormalized,
        createdByCaregiverUid: caregiverUid,
        createdAt: now,
        updatedAt: now,
      }, {merge: true});

      batch.set(db.collection("patients").doc(patientUid), {
        uid: patientUid,
        patientId,
        ownerUid: patientUid,
        name,
        email,
        phone,
        phoneNormalized,
        chronicCondition,
        arabicMode: true,
        largeFonts: false,
        highContrast: false,
        caregiverAlertsEnabled: true,
        createdByCaregiverUid: caregiverUid,
        createdAt: now,
        updatedAt: now,
      }, {merge: true});

      batch.set(db.collection("patientDirectory").doc(patientUid), {
        patientUid,
        patientId,
        name,
        phone,
        phoneNormalized,
        updatedAt: now,
      }, {merge: true});

      batch.set(
        db.collection("patientCaregivers").doc(`${patientUid}_${caregiverUid}`),
        {
          patientUid,
          patientId,
          caregiverUid,
          linkedAt: now,
          createdByCaregiver: true,
        },
        {merge: true},
      );

      batch.set(
        db.collection("patients")
          .doc(patientUid)
          .collection("caregivers")
          .doc(caregiverUid),
        {
          caregiverUid,
          patientUid,
          patientId,
          name: caregiver.name || "Caregiver",
          email: caregiver.email || "",
          phone: caregiver.phone || "",
          relationship: "Caregiver",
          permission: "all",
          linkedAt: now,
        },
        {merge: true},
      );

      batch.update(snapshot.ref, {
        status: "complete",
        patientUid,
        patientId,
        password: admin.firestore.FieldValue.delete(),
        completedAt: now,
      });

      await batch.commit();
    } catch (error) {
      logger.error("Patient account creation failed", {
        requestId: event.params.requestId,
        error: error.message,
      });
      await snapshot.ref.set({
        status: "error",
        password: admin.firestore.FieldValue.delete(),
        error: String(error.message || error),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  },
);

exports.notifyPatientMedicationChange = onDocumentWritten(
  "patients/{patientUid}/medications/{medicationId}",
  async (event) => {
    const after = event.data && event.data.after;
    if (!after || !after.exists) return;
    const medication = after.data();
    const actorRole = String(medication.actorRole || "");
    if (actorRole !== "caregiver" && actorRole !== "doctor") return;

    const patientUid = event.params.patientUid;
    const patientDoc = await admin
      .firestore()
      .collection("patients")
      .doc(patientUid)
      .get();
    const token = patientDoc.get("deviceToken");
    if (!token) {
      logger.warn("Patient has no FCM token for medication change", {
        patientUid,
        medicationId: event.params.medicationId,
      });
      return;
    }

    const title = actorRole === "doctor" ?
      "تم تحديث الدواء من الطبيب" :
      "تم تحديث الدواء من مقدم الرعاية";
    const body = `${medication.name || "دواء"} تمت إضافته أو تحديثه.`;

    await admin.messaging().send({
      token,
      notification: {title, body},
      data: {
        type: "medicationChanged",
        patientUid,
        medicationId: String(event.params.medicationId),
        actorRole,
        medicationName: String(medication.name || ""),
        language: "ar",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "med360_reminders",
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
  },
);

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
          "تنبيه جرعة فائتة" :
          "Missed Medication Alert",
        body: latestDose.language === "ar" ?
          `${latestDose.patientName || "Patient"} فاتته جرعة ${latestDose.medicationName || "دواء مجدولة"}.` :
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
