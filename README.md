# DocsSaver 📁✨

A modern, offline-first personal knowledge and document management mobile application built with Flutter, following Clean Architecture principles.

## 🌟 Key Features
- **Smart Document Scanning:** Google ML Kit document scanner integration.
- **Multi-modal Capture:** Fast capture for Notes, Audio/Voice recordings, Web Links, Photos, and Videos.
- **Semantic & Visual Search:** Instant search by context, meaning, or feeling.
- **Categorization & Bookmarking:** Save, organize, pin, and retrieve critical memories seamlessly.
- **Deep Sage Pine Design:** Consistent, cohesive modern theme with adaptive dark and light mode support.

## 🏛️ Architecture
DocsSaver strictly adheres to Feature-First Clean Architecture:
- **Presentation Layer:** BLoC/Cubit pattern, responsive widgets, and adaptive theming.
- **Domain Layer:** Pure Dart entities, use cases, and abstract repository contracts.
- **Data Layer:** Remote data sources (Supabase/APIs), Local cache (Isar), data models, and repository implementations.

## 🛠️ Tech Stack & Dependencies
- **Framework:** Flutter (Dart)
- **State Management:** flutter_bloc
- **Theme Primary:** Deep Sage Pine (`#134E3F`)
- **Local Storage:** Isar Database / SharedPreferences

## 🚀 Getting Started
1. Clone the repository:
   ```bash
   git clone <repo_url>
   cd docs_saver
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```
