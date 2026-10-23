// Push notifications on the website (Firebase Cloud Messaging): shows a
// notification while HUNTR isn't open, and opens HUNTR at the right place
// when it's clicked. The backend sends each notification's text and its
// link (`fcm_options.link`); Firebase shows it. The config is the web app's
// public one (lib/config/firebase_config.dart).
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDrGiHW6iTyN9PEia-P8w3jLrklvhrNGUU',
  authDomain: 'huntr-e9ae3.firebaseapp.com',
  projectId: 'huntr-e9ae3',
  storageBucket: 'huntr-e9ae3.firebasestorage.app',
  messagingSenderId: '257912667122',
  appId: '1:257912667122:web:fd9c6ff289c62b30dec96b',
});

firebase.messaging();
