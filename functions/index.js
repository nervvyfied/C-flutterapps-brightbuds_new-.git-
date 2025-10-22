const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendNotification = functions.firestore
    .document("notification_jobs/{docId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();

      const token = data.token;
      const title = data.title;
      const body = data.body;
      const extraData = data.data || {};

      if (!token) {
        console.log("❌ No FCM token provided.");
        return null;
      }

      const message = {
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: extraData,
      };

      try {
        await admin.messaging().send(message);
        console.log(`✅ Notification sent to ${token}: ${title}`);
      } catch (error) {
        console.error("🔥 Error sending notification:", error);
      }

      return null;
    });
