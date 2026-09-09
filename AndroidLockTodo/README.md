# LockTodo Android

Free local Android companion app for LockTodo.

## What Works

- Opens as a normal Android app.
- Shows a local todo list.
- Adds local Android-only tasks.
- Checks and unchecks tasks.
- Imports the JSON file exported from the iOS LockTodo app.

## iOS To Android Flow

1. On iPhone, open LockTodo.
2. Go to Settings > Android 공유.
3. Tap `Android용 할 일 파일 만들기`.
4. Send the generated JSON file to the Android device.
5. Open that JSON file with LockTodo Android.

This is intentionally server-free and free to run. Real-time iPhone-to-Android sync would require a shared backend or cloud account.

## Build

Open this `AndroidLockTodo` folder in Android Studio and run the `app` configuration.

The app uses only the Android platform SDK and the Android Gradle Plugin. It does not use paid map APIs, external databases, or subscriptions.
