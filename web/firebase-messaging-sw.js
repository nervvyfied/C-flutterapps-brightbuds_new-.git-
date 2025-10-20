// Give the service worker access to Firebase Messaging.
importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js');

// Initialize Firebase app in the service worker
firebase.initializeApp({
  apiKey: "AIzaSyARR59BlH2uNllBtL-rjW3xAalkGfHa2NU",
  authDomain: "brightbuds-15065.firebaseapp.com",
  projectId: "brightbuds-15065",
  storageBucket: "brightbuds-15065.firebasestorage.app",
  messagingSenderId: "953113321611",
  appId: "1:953113321611:web:f281cdf043d866e4ce748e"
});

// Retrieve Firebase Messaging object.
const messaging = firebase.messaging();

// Optional: handle background messages (when the web app is closed)
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);

  const notificationTitle = payload.notification?.title || 'BrightBuds Notification';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/assets/profile_placeholder.png', // optional
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
