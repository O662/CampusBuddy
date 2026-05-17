# CampusBuddy 🎓

A calm, glassmorphic companion app that helps students navigate college —
dashboard, planner, study tools, grades, and focus, all in one place.

Built with Flutter for **Windows**, **Linux**, **Android (tablet)**, and the
**Web**. All data is stored **locally on the device** (Hive) — no account, no
cloud, no sign-in.

## Highlights

- **Animated gradient + frosted glass** — a slow, relaxing drifting backdrop
  with soft "aurora" blobs behind translucent glass panels.
- **Two-menu navigation** — a vertical rail on the left (Dashboard · Planner ·
  Study) and a horizontal menu top-right (To-do · Timer · Grades · Focus),
  with a profile button that opens Profile & Settings.
- **Dashboard** — greeting, quick stats, today's agenda, upcoming
  assignments, grade progress bars, open tasks, and upcoming events.
- **Planner** — month calendar + a Sunday→Saturday week grid. Drag an
  assignment from the side list onto any day, then drag the block along the
  day and resize it from the bottom handle to block out study time.
- **Study** — create decks and flashcards; study with a Leitner
  spaced-repetition box system (correct answers graduate cards, misses reset
  them).
- **Grades** — courses with weighted averages and per-item entries.
- **Timer** — a Pomodoro focus/break timer driven by your preferences.
- **Focus** — a quiet breathing space with a guided breathing circle.
- **Profile** — name/school/major plus study-goal and session-length settings.

Shared data: assignments added from the Dashboard, Planner, or To-do all live
in the same store, so they show up everywhere.

## Project layout

```
lib/
  main.dart                  app entry, window sizing, Hive init
  app/                       router + navigation shell (the two menus)
  core/theme/                palette + theme
  core/widgets/              animated background, glass widgets, dialogs
  data/                      models + Hive local store
  state/                     Riverpod providers
  features/                  one folder per page
```

## Running it

Prerequisites: Flutter 3.38+ (Dart 3.10+). Then from the project root:

```bash
flutter pub get

# Desktop
flutter run -d windows
flutter run -d linux

# Web
flutter run -d chrome

# Android tablet (device/emulator connected)
flutter run -d <device-id>
```

### Building release artifacts

```bash
flutter build windows
flutter build linux
flutter build web
flutter build apk        # or: flutter build appbundle
```

## Notes

- First launch seeds a small friendly sample dataset (courses, assignments,
  events, a flashcard deck) so every page has something to show. Everything
  is editable and the seed only runs once.
- State management: Riverpod. Navigation: go_router. Local storage: Hive CE.
  No code generation is used, which keeps the web build simple.

## Weather widget

The dashboard Weather card works with **zero setup**:

- On first open it **auto-detects your location** from your IP (no key, no
  GPS permission, works on Windows/Linux/Android/Web). IP location is
  city-level/approximate — fine for weather.
- Forecast data comes from **Open-Meteo** (free, no account, no API key).
- You can override the location any time: card menu (⋯) → **Search a city**.
  The search lists multiple matches, so small towns work too — not just
  major cities. Or pick **Update to my location** to re-detect.
- Tap the temperature to toggle °C / °F.

### Optional: use OpenWeatherMap instead

Open-Meteo is recommended and needs nothing. If you'd rather use
OpenWeatherMap:

1. Create a free account at <https://openweathermap.org/api>.
2. In your account, open **API keys** and copy your key.
3. In the app: Weather card menu (⋯) → **Weather provider** → paste the key
   → **Save**. (Leave it blank / press **Use Open-Meteo** to switch back.)

Note: brand-new OpenWeatherMap keys can take ~1–2 hours to activate — until
then it will report an invalid key. The key is stored locally on the device
only.
