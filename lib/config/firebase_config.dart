/// The Firebase project for push notifications (Firebase Cloud Messaging):
/// the website's web-app config, from the Firebase console (Project settings
/// > Your apps > HUNTR Web). These are public - they ship inside the site.
/// The Android app reads its own from android/app/google-services.json.
class FirebaseWebConfig {
  static const apiKey = 'AIzaSyDrGiHW6iTyN9PEia-P8w3jLrklvhrNGUU';
  static const authDomain = 'huntr-e9ae3.firebaseapp.com';
  static const projectId = 'huntr-e9ae3';
  static const storageBucket = 'huntr-e9ae3.firebasestorage.app';
  static const messagingSenderId = '257912667122';
  static const appId = '1:257912667122:web:fd9c6ff289c62b30dec96b';

  /// The Web Push certificate's public key (Project settings > Cloud
  /// Messaging > Web Push certificates).
  static const vapidKey =
      'BAJ1QLBh7GDxuCuw7FIxFvvz8pS5ND1O_JIp6Pn92Z7N-7bVWDrf43mPtqHWv0OcntLfcWXubc6GiGqxZsiDBMg';
}
