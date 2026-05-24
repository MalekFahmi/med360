"use strict";

const http = require("http");
const admin = require("firebase-admin");

const pollIntervalSeconds = numberFromEnv("POLL_INTERVAL_SECONDS", 60);
const autoMissDelayMinutes = numberFromEnv("AUTO_MISS_DELAY_MINUTES", 5);
const maxDosesPerPoll = numberFromEnv("MAX_DOSES_PER_POLL", 100);
const maxNotificationsPerPoll = numberFromEnv("MAX_NOTIFICATIONS_PER_POLL", 100);
const port = numberFromEnv("PORT", 8080);

const state = {
  startedAt: new Date().toISOString(),
  lastPollAt: null,
  lastSuccessAt: null,
  lastError: null,
  running: false,
  polls: 0,
  missedDoses: 0,
  notificationsCreated: 0,
  pushesSent: 0,
};

initFirebase();

const db = admin.firestore();
const messaging = admin.messaging();

startHealthServer();
runPoll();
setInterval(runPoll, pollIntervalSeconds * 1000);

function initFirebase() {
  if (admin.apps.length > 0) return;

  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
  if (encoded) {
    const json = Buffer.from(encoded, "base64").toString("utf8");
    const credential = admin.credential.cert(JSON.parse(json));
    admin.initializeApp({credential});
    return;
  }

  admin.initializeApp();
}

function startHealthServer() {
  const server = http.createServer((request, response) => {
    if (request.url !== "/health") {
      response.writeHead(404, {"content-type": "application/json"});
      response.end(JSON.stringify({error: "not-found"}));
      return;
    }

    response.writeHead(200, {"content-type": "application/json"});
    response.end(JSON.stringify(state));
  });

  server.listen(port, () => {
    console.log(`MED360 worker health server listening on :${port}`);
  });
}

async function runPoll() {
  if (state.running) {
    console.log("Previous poll is still running; skipping this tick.");
    return;
  }

  state.running = true;
  state.lastPollAt = new Date().toISOString();
  state.polls += 1;

  try {
    const missed = await markOverdueDosesMissed();
    const pushed = await deliverPendingNotifications();
    state.missedDoses += missed.missedDoses;
    state.notificationsCreated += missed.notificationsCreated;
    state.pushesSent += pushed;
    state.lastSuccessAt = new Date().toISOString();
    state.lastError = null;
    console.log(
      `Poll complete: missed=${missed.missedDoses}, ` +
        `notifications=${missed.notificationsCreated}, pushed=${pushed}`,
    );
  } catch (error) {
    state.lastError = error.stack || String(error);
    console.error("Poll failed:", error);
  } finally {
    state.running = false;
  }
}

async function markOverdueDosesMissed() {
  const cutoff = new Date(Date.now() - autoMissDelayMinutes * 60 * 1000);
  const snapshot = await db
    .collection("patientDoses")
    .where("status", "==", "pending")
    .where("scheduledAt", "<=", admin.firestore.Timestamp.fromDate(cutoff))
    .limit(maxDosesPerPoll)
    .get();

  let missedDoses = 0;
  let notificationsCreated = 0;

  for (const doc of snapshot.docs) {
    const result = await markDoseMissed(doc.ref);
    if (result.markedMissed) missedDoses += 1;
    notificationsCreated += result.notificationsCreated;
  }

  return {missedDoses, notificationsCreated};
}

async function markDoseMissed(doseRef) {
  const now = new Date();
  let latestDose = null;
  let markedMissed = false;

  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(doseRef);
    if (!latest.exists) return;

    const dose = latest.data();
    if (!dose || dose.status !== "pending") return;

    latestDose = dose;
    markedMissed = true;
    transaction.set(
      doseRef,
      {
        status: "missed",
        confirmedAt: now.toISOString(),
        caregiverNotified: shouldNotifyCaregivers(dose),
        secondReminderSent: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });

  if (!markedMissed || !shouldNotifyCaregivers(latestDose)) {
    return {markedMissed, notificationsCreated: 0};
  }

  const notificationsCreated = await createCaregiverNotifications(
    latestDose,
    now,
  );
  return {markedMissed, notificationsCreated};
}

async function createCaregiverNotifications(dose, now) {
  const caregiverIds = Array.isArray(dose.caregiverIds) ? dose.caregiverIds : [];
  if (caregiverIds.length === 0) return 0;

  const batch = db.batch();
  let count = 0;

  for (const caregiverUid of caregiverIds) {
    if (!caregiverUid) continue;

    const notificationId = `MISS-${dose.id}-${caregiverUid}`;
    const payload = missedDosePayload({
      dose,
      caregiverUid,
      notificationId,
      now,
    });

    const inboxRef = db
      .collection("caregiverInboxes")
      .doc(caregiverUid)
      .collection("notifications")
      .doc(notificationId);
    batch.set(inboxRef, payload, {merge: true});

    if (dose.ownerUid) {
      const patientAlertRef = db
        .collection("patients")
        .doc(String(dose.ownerUid))
        .collection("caregiverNotifications")
        .doc(notificationId);
      batch.set(patientAlertRef, payload, {merge: true});
    }

    count += 1;
  }

  await batch.commit();
  return count;
}

async function deliverPendingNotifications() {
  const snapshot = await db
    .collectionGroup("notifications")
    .where("delivered", "==", false)
    .limit(maxNotificationsPerPoll)
    .get();

  let pushed = 0;
  for (const doc of snapshot.docs) {
    if (!isCaregiverInboxNotification(doc)) continue;

    const notification = doc.data();
    if (!notification) continue;

    const caregiverUid = notification.caregiverId || caregiverUidFromPath(doc);
    if (!caregiverUid) continue;

    const sent = await sendCaregiverPush({
      caregiverUid,
      notificationId: doc.id,
      notification,
      notificationRef: doc.ref,
    });
    if (sent) pushed += 1;
  }

  return pushed;
}

async function sendCaregiverPush({
  caregiverUid,
  notificationId,
  notification,
  notificationRef,
}) {
  const caregiverDoc = await db.collection("users").doc(caregiverUid).get();
  const token = caregiverDoc.get("fcmToken");

  if (!token) {
    await notificationRef.set(
      {
        delivered: false,
        deliveryError: "missing-fcm-token",
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return false;
  }

  const title = notification.title || "Missed Medication Alert";
  const body =
    notification.body ||
    `${notification.patientName || "Patient"} missed a scheduled medication.`;

  try {
    const response = await messaging.send({
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

    await notificationRef.set(
      {
        delivered: true,
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        deliveryError: admin.firestore.FieldValue.delete(),
        messageId: response,
      },
      {merge: true},
    );
    return true;
  } catch (error) {
    await notificationRef.set(
      {
        delivered: false,
        deliveryError: error.code || error.message || String(error),
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    console.error("FCM send failed:", caregiverUid, notificationId, error);
    return false;
  }
}

function missedDosePayload({dose, caregiverUid, notificationId, now}) {
  const patientName = String(dose.patientName || "Patient");
  const medicationName = String(dose.medicationName || "medication");
  const isArabic = dose.language === "ar";

  return {
    id: notificationId,
    caregiverId: caregiverUid,
    patientId: String(dose.patientId || ""),
    patientUid: String(dose.ownerUid || ""),
    patientName,
    medicationId: String(dose.medicationId || ""),
    medicationName,
    missedAt: now.toISOString(),
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    channel: "both",
    acknowledged: false,
    title: isArabic ? "Missed Medication Alert" : "Missed Medication Alert",
    body: isArabic ?
      `${patientName} missed ${medicationName}.` :
      `${patientName} missed ${medicationName}.`,
    language: String(dose.language || "en"),
    type: "missedDose",
    delivered: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function shouldNotifyCaregivers(dose) {
  return (
    dose &&
    dose.caregiverAlertsEnabled === true &&
    Array.isArray(dose.caregiverIds) &&
    dose.caregiverIds.length > 0 &&
    dose.caregiverNotified !== true
  );
}

function caregiverUidFromPath(doc) {
  const segments = doc.ref.path.split("/");
  const inboxIndex = segments.indexOf("caregiverInboxes");
  if (inboxIndex < 0 || inboxIndex + 1 >= segments.length) return null;
  return segments[inboxIndex + 1];
}

function isCaregiverInboxNotification(doc) {
  const segments = doc.ref.path.split("/");
  return (
    segments.length >= 4 &&
    segments[0] === "caregiverInboxes" &&
    segments[2] === "notifications"
  );
}

function numberFromEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}
