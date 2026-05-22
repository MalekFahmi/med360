/**
 * Cloud Function to send FCM push notifications to caregivers.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendCaregiverNotification = functions.firestore
    .document("caregiverInboxes/{caregiverUid}/notifications/{notificationId}")
    .onCreate(async (snapshot, context) => {
      const data = snapshot.data();
      const caregiverUid = context.params.caregiverUid;

      // 1. Get caregiver's FCM token
      const userDoc = await admin.firestore()
          .collection("users")
          .doc(caregiverUid)
          .get();

      if (!userDoc.exists) {
        console.log("Caregiver user not found:", caregiverUid);
        return null;
      }

      const fcmToken = userDoc.data().fcmToken;
      if (!fcmToken) {
        console.log("FCM token not found for caregiver:", caregiverUid);
        return null;
      }

      // 2. Prepare notification content
      let title = "MED360 Alert";
      let body = "You have a new notification.";

      if (data.type === "missedDose") {
        const isAr = data.language === "ar";
        title = isAr ? "تنبيه جرعة فائتة" : "Missed Medication Alert";
        body = isAr ?
            `فاتت جرعة ${data.medicationName} للمريض ${data.patientName}` :
            `${data.patientName} missed a scheduled medication: ${data.medicationName}`;
      } else if (data.type === "caregiverAdded") {
        const isAr = data.language === "ar";
        title = isAr ? "تمت إضافتك كمراقب" : "New Patient Linked";
        body = isAr ?
            `تمت إضافتك كمراقب للمريض ${data.patientName}` :
            `You have been linked as a caregiver for ${data.patientName}`;
      }

      // 3. Send message
      const message = {
        token: fcmToken,
        notification: {
          title: title,
          body: body,
        },
        data: {
          notificationId: data.id,
          type: data.type,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      };

      try {
        const response = await admin.messaging().send(message);
        console.log("Successfully sent notification:", response);
        return snapshot.ref.update({delivered: true, deliveredAt: admin.firestore.FieldValue.serverTimestamp()});
      } catch (error) {
        console.error("Error sending notification:", error);
        return null;
      }
    });
