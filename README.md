# Huntr

Meet people right around you. A Flutter app with **Explore** (who's nearby) and **Chat**, built to be simpler and friendlier than the usual grid apps.

## What's in it

- **Onboarding in 3 short steps:** what Huntr is, your name and age (18+ confirmation), and what you're here for (chat, friends, dates, networking, relationship).
- **Explore:** a grid of people sorted by distance, with online dots, verified badges and a live "people online near you" count.
  - One-tap quick filters: *Online now*, *Within 5 km*, *Chat*, *Friends*, *Dates*.
  - A full filter sheet (distance, age range, looking for), search by name, bio or interest, and pull to refresh.
  - A favorites row, plus a friendly empty state when no one matches.
- **Profiles:** a large portrait, status, distance, pronouns, height, album, about, looking for and interests.
  - A thumb-reach action button that changes with the connection: **Send chat request** → **Request sent** → **Message**, or **Accept / Decline** for requests you received.
  - Favorite, report (with reasons) and block (with confirmation).
- **Chat requests and albums:** you can't message someone until they accept your chat request.
  - Send a request from their profile, with an optional note.
  - Their private album is blurred until then.
  - When they accept, their album is sent into the chat automatically, and you can both start messaging.
  - Requests you receive appear under **Chats → Requests**. Accepting sends *your* album to them.
  - You can decline a request you received, or cancel one you sent.
  - Manage your own album under **Me** (sample photos until uploads exist).
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

## Status

This is a working prototype. People, conversations and replies are **sample data** (`lib/data/sample_data.dart`), and all state lives in `lib/state/app_state.dart`. Screens only talk to `AppState`, so a real backend can replace it without touching the UI. Next steps:

- Accounts and auth
- Location for real distances
- Photo upload
- A realtime chat backend
- Push notifications
- Server-side moderation for reports and blocks

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
