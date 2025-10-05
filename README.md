# Pay Go

A Flutter-based social application with chat and post sharing functionalities.

## Features

- **Authentication:** Secure user login and registration.
- **Chat:** Real-time chat with other users.
- **Feed:** A feed to view posts from other users.
- **Post Creation:** Create and share your own posts.
- **User Profiles:** View and manage user profiles.

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- A Firebase project.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    ```
2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Configure Firebase:**
    - Create a new Firebase project at [https://console.firebase.google.com/](https://console.firebase.google.com/).
    - Add an Android app to your Firebase project with the package name `com.example.pay_go` (you can find the package name in `android/app/build.gradle.kts`).
    - Download the `google-services.json` file and place it in the `android/app` directory.
    - Add an iOS app to your Firebase project with the bundle ID `com.example.payGo` (you can find the bundle ID in Xcode under `General > Identity > Bundle Identifier`).
    - Download the `GoogleService-Info.plist` file and place it in the `ios/Runner` directory.

### Running the Application

```bash
flutter run
```

### Configuring the API endpoint

`ApiService` now resolves the backend base URL at runtime:

- Android emulators default to `http://10.0.2.2:3000/api`.
- Physical Android devices default to `http://192.168.29.103:3000/api`.
- iOS simulators, desktop, and web builds default to `http://localhost:3000/api`.

If your LAN IP changes, launch with an override:

```bash
flutter run --dart-define=API_DEVICE_BASE_URL=http://192.168.29.103:3000/api
```

You can also override specific environments:

- `API_BASE_URL` – global override for every platform.
- `API_EMULATOR_BASE_URL` – override only emulator/simulator builds.
- `API_WEB_BASE_URL` – override web builds.

All overrides are normalized automatically, so both URLs with and without a
trailing `/` are supported.

## Project Structure

```
lib/
├── pages/
│   ├── addpostpage.dart      # Page for creating new posts
│   ├── auth_gate.dart        # Handles authentication state
│   ├── chat_list_page.dart   # Lists all chats
│   ├── chat_screen.dart      # The chat screen for a single conversation
│   ├── feed_page.dart        # The main feed page
│   ├── homepage.dart         # The home page
│   ├── login_or_register.dart # Handles switching between login and signup
│   ├── login.dart            # The login page
│   ├── profile_page.dart     # The user profile page
│   └── signup.dart           # The signup page
├── services/
│   └── api_service.dart      # Service for API calls
├── firebase_options.dart     # Firebase configuration
└── main.dart                 # The main entry point of the application
```

## Dependencies

- [flutter](https://pub.dev/packages/flutter)
- [cupertino_icons](https://pub.dev/packages/cupertino_icons)
- [image_picker](https://pub.dev/packages/image_picker)
- [firebase_core](https://pub.dev/packages/firebase_core)
- [firebase_auth](https://pub.dev/packages/firebase_auth)
- [cloud_firestore](https://pub.dev/packages/cloud_firestore)
- [firebase_storage](https://pub.dev/packages/firebase_storage)
- [http_parser](https://pub.dev/packages/http_parser)

---

This project was generated with Flutter. For more information on Flutter, see the [official documentation](https://flutter.dev/docs).
