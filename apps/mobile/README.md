# Fix Loop mobile client

The Stitch designs are wired to the Fix Loop REST API (`apps/api`) for Android
and Web using the `http` package, Bearer JWTs, and silent refresh-token rotation
on `401`. It uses the included open-licensed Bricolage Grotesque and Atkinson
Hyperlegible Next fonts (`assets/fonts/`) and adapts to the system light/dark
theme.

The mobile client **never** receives database passwords or Supabase credentials;
all requests go strictly through `API_BASE_URL` (default `http://localhost:8080`).

Target toolchain: Flutter **3.41.9** / Dart **3.11.5**. From this folder:

```sh
flutter create --no-pub --platforms=android,web --project-name fixloop_mobile --org com.fixloop .
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port 3000 --dart-define=API_BASE_URL=http://localhost:8080
```

When running Flutter Web locally against the API, configure
`ALLOWED_WEB_ORIGINS=http://localhost:3000,http://127.0.0.1:3000` in the API
environment (`.env`) so browser CORS requests succeed.

For web without Chrome detected by Flutter, use:

```sh
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3000 --dart-define=API_BASE_URL=http://localhost:8080
```

For Android emulator pointing at an API on your host machine:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Widget tests (`flutter test`) inject `FakeFixLoopApi` (`lib/data/fake_fix_loop_api.dart`)
and `FakePhotoPicker` so the entire UI, routing flow, staff queue, analytics,
notifications, missing-attachment placeholders, dark mode, and small-viewport
overflow safety run deterministically without network access.
