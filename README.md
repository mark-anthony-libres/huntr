# Huntr

Meet people right around you. A Flutter app with **Explore** (who's nearby) and **Chat**, built to be simpler and friendlier than the usual grid apps.

## What's in it

- **Google sign-in:** authenticate with a Google account and prefill your onboarding name; Facebook remains a demo-only button. Huntr never posts to social media.
- **Onboarding in 3 short steps:** what Huntr is, your name and age (18+ confirmation), and what you're here for (chat, friends, dates, networking, relationship).
- **Explore:** a grid of people sorted by distance, with online dots, verified badges and a live "people online near you" count.
  - One-tap quick filters: *Online now*, *Within 5 km*, *Chat*, *Friends*, *Dates*.
  - A full filter sheet (distance, age range, looking for), search by name, bio or interest, and pull to refresh.
  - A favorites row, plus a friendly empty state when no one matches.
- **Profiles:** a photo gallery, status, distance, pronouns, height, about, looking for and interests.
  - A thumb-reach action button that changes with the connection: **Send chat request** → **Request sent** → **Message**, or **Accept / Decline** for requests you received.
  - Favorite, report (with reasons) and block (with confirmation).
- **Profile photos:** several public pictures per person.
  - Shown unblurred on the profile as a gallery: swipe, or tap left/right, with a page indicator at the top.
  - Manage your own under **Me**: add, remove, and tap one to make it your main photo (up to 6).
- **Private albums:** separate from the profile and never shown on it.
  - Create as many named albums as you like under **Me → My albums** ("Weekend", "Gym", …).
  - Add or remove photos, rename, or delete an album.
- **Chat requests:** you can't message someone until they approve your request.
  - When sending, pick which of your albums to send, and add an optional note.
  - When accepting (from the profile or **Chats → Requests**), pick which of your albums to send back.
  - **On approval, both chosen albums are sent to each other automatically**, and the chat opens.
  - You can decline a request you received, cancel one you sent, or choose not to share an album.
- **Chats:** an inbox with unread badges, an online-now row, search, an *Unread* filter, swipe to delete, and a typing indicator.
- **Chat screen:** message bubbles with grouping, timestamps, sent/read status, large emoji, an animated typing indicator, and quick-reply chips so the first message is easy.
- **Me:** edit name and bio, privacy switches (show distance, show online status), safety tips.
- Dark theme with a warm amber-to-coral accent; works on phones, tablets and the web.

## Run

```
flutter pub get
flutter run            # Android / iOS device or emulator
flutter run -d chrome  # web
flutter test
```

### Which backend the app talks to

The backend URL comes from a `--dart-define-from-file` file in `env/`:

| File | Backend | Used by |
|---|---|---|
| `env/dev.json` | `http://localhost:18000/api` | Chrome (VS Code launch config) |
| `env/phone.json` | `http://localhost:18000/api` | A phone over wireless debugging (`adb reverse`, see `tool/connect_phone.ps1`) |
| `env/android.json` | `http://10.0.2.2:18000/api` | The Android emulator |
| `env/prod.json` | `https://152-42-229-3.sslip.io/api` | Release builds and the hosted web app |

```
flutter run -d chrome --dart-define-from-file=env/dev.json
```

## Status

The app is connected to the HUNTR backend (the separate `huntr-backend` repository) for sign-in sessions, profiles, photos, albums, Explore, location, chat and presence (`lib/services/`). Some parts still read sample data (`lib/data/sample_data.dart`). Not yet built: push notifications.

## Production

| Part | Address | Deploy |
|---|---|---|
| Web app | https://huntr.marklibres345.workers.dev | `tool/deploy_web.sh` (this repository) |
| Backend API | https://152-42-229-3.sslip.io | `./deploy.sh` (in `huntr-backend`) |

### Web app

Hosted on Cloudflare Workers static assets (`wrangler.jsonc`). From Git Bash:

```
npx wrangler@4 login      # first time only
tool/deploy_web.sh        # builds with env/prod.json and uploads build/web
```

If the browser shows an old version after a deploy, reload with Ctrl+Shift+R.

### Android

Build or install against production:

```
flutter build apk --release --dart-define-from-file=env/prod.json
flutter run --release --dart-define-from-file=env/prod.json -d <device>
```

Release builds are currently signed with the debug key (`android/app/build.gradle.kts`). Before publishing to the Play Store, create a release keystore, sign with it, and add its SHA-1 to the Android OAuth client (see below).

## Google OAuth setup

Google client IDs are public app configuration, not secrets. Set them once in `assets/google_oauth.json`; you can then launch the app normally without adding OAuth defines to every `flutter run` command.

1. Open [Google Cloud Console → Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients), create or select a project, and configure the consent screen under **Branding** and **Audience**. While testing, add your Google account as a test user.
2. Create the relevant OAuth clients below. Do not create or put an OAuth **client secret** in the Flutter app.
3. Fill in the client IDs in `assets/google_oauth.json`:

   ```json
   {
     "webClientId": "WEB_CLIENT_ID.apps.googleusercontent.com",
     "iosClientId": "IOS_CLIENT_ID.apps.googleusercontent.com",
     "androidServerClientId": "WEB_CLIENT_ID.apps.googleusercontent.com"
   }
   ```

   The Android server client ID is the **Web application** client ID; the Android Google Sign-In SDK requires it, and the backend verifies sign-ins against it (`GOOGLE_CLIENT_IDS` in the backend `.env`). The app uses each platform's client ID where appropriate.

### Web

- Create a **Web application** OAuth client.
- In **Authorized JavaScript origins**, add every origin you open Huntr from: `http://localhost:7357` for local development with the command below, and `https://huntr.marklibres345.workers.dev` for the hosted web app. Origins have no path or query string. A missing origin shows Google's `Error 400: origin_mismatch`.
- The backend must also allow the origin: add it to `CORS_ORIGINS` in the server's `.env`.
- Put this client's ID in both `webClientId` and `androidServerClientId` in `assets/google_oauth.json`.
- Run normally, optionally pinning a stable local port:

  ```
  flutter run -d chrome --web-hostname localhost --web-port 7357
  ```

The web app uses Google's hosted sign-in button as required by Google Identity Services.

### Android

- Create an **Android** OAuth client with package name `com.marklibres.huntr`.
- Add the SHA-1 signing certificate fingerprint. For local debug builds, run `cd android` then `.\gradlew signingReport` in PowerShell, and copy the SHA-1 from the `debug` variant. Add a separate fingerprint for every signing key used to distribute the app.
- Set `androidServerClientId` to the **Web application** client ID (same value as `webClientId` above).

### iOS

- Create an **iOS** OAuth client with the app's bundle identifier. Check the effective bundle identifier in Xcode under **Runner → Signing & Capabilities**.
- Put this client's ID in `iosClientId` in `assets/google_oauth.json`.
- Copy the corresponding **iOS URL scheme** (the reversed client ID) from Google Cloud Console into `GOOGLE_REVERSED_CLIENT_ID` in `ios/Flutter/GoogleOAuth.xcconfig`.

After saving the configuration, run `flutter pub get` if prompted by Flutter, then run the app as usual. `assets/google_oauth.json` is included in the app bundle, so treat these values as public; never put client secrets or backend credentials there.

## Structure

```
lib/
  main.dart                 app + onboarding gate
  theme.dart                colors and Material 3 theme
  models/models.dart        Profile, Message, Conversation, ExploreFilters
  data/sample_data.dart     seeded sample people and replies
  state/app_state.dart      app state + AppScope (InheritedNotifier)
  widgets/                  avatar, profile tile
  screens/                  onboarding, explore, profile, chats, chat, me, home shell
test/app_test.dart          onboarding, filters, chat, block
```
