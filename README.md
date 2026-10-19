# PathMap Learn — Flutter

Native Flutter adaptation of [abayomiabiodun/Pathmap-Learn](https://github.com/abayomiabiodun/Pathmap-Learn).

## Run

With a stable Flutter SDK on PATH:

```sh
flutter pub get
flutter run
```

The workspace also includes an ignored SDK at `.tools/flutter`. On this Windows computer:

```powershell
.\.tools\flutter\bin\flutter.bat run -d chrome
```

For Android, install Android Studio and its SDK, start an emulator or attach a device, then run `flutter run`. Build an installable Android package with `flutter build apk --release`. iOS requires macOS and Xcode; run `flutter build ios` there and configure signing.

## Included

- Material 3 UI using the original green, amber and warm neutral palette, with dark appearance.
- Learning Library, accessible from the header library icon and My course, displays all ten courses with descriptions, lesson counts, access status and searchable translated titles. Every course outline can be previewed without changing enrollment or unlocking full lessons.
- Ten interactive course activities using real lesson explanations, examples and true/false challenges. Learners try each activity before rating their interest. Feedback supports beginners; correctness does not reduce an interest match.
- The strongest positive interest rating identifies one provisional course match. Tied top interests require choosing one of those matches; an all-zero result assigns no course. Partial quiz drafts persist. A retake changes the match only when its new result is accepted.
- After matching, the home page celebrates “I've found my path” and opens a Taster before full learning. The matched course's next three lesson topics become a three-star challenge game with unlimited retries, followed by a small practical task and an explicit interest confirmation. Taster stars and practice drafts persist across restarts, use the selected language, and never award course completions, streaks or learning points.
- “Yes, this is my path” unlocks the full matched course after three earned stars and at least 20 characters of practice. Unsure learners can replay; learners who dislike the path can retake the assessment. Accepting a new quiz result requires a new taster confirmation. Confirmation is bound to that specific assessment, not just its course name.
- My course and Return to learning show only the assessed, taster-confirmed course and resume the next unfinished lesson. Course pages, lesson pages, draft writes and completion writes enforce both the match and taster confirmation. Earlier manual path choices require the activity assessment; earlier learning work is preserved.
- All 100 original lessons and the full app interface are bundled in English, Nigerian Pidgin, Yoruba, Hausa, Igbo and French. Choose App language in You to switch immediately. The choice persists across restarts; drafts and progress remain intact.
- Offline lesson reading, practice drafts, true/false knowledge checks, device progress, points and a Lagos-calendar learning streak.
- Completion requires 20 characters of practice and a correct knowledge check. Repeating a completed lesson does not award additional points.
- Adaptive centred layouts for phones and wider screens.
- Circles accounts on the local shared service: discover peers with the same interest, invite them to a twelve-person circle, and accept or decline incoming invitations. Large Share your work and Find a mentor shortcuts appear immediately under the Circles heading; posting opens the editor directly and mentoring jumps to its directory.
- Volunteer mentor offers, same-path mentor discovery, private mentoring requests, and mentor-controlled acceptance or decline. Volunteer experience is self-described rather than independently verified.
- Circle work feeds with author-only editing and deletion. Posts award 10 account points each, up to 30 per Lagos calendar day. Editing earns no extra points, deleting removes the award, and reposting identical normalized content never earns again. Progress combines these account posting points with device lesson points.

## Circles service

Start the shared local API in a separate terminal:

```sh
python server/circles_api.py --port 8090
```

Serve the web build on the same computer, for example:

```sh
flutter build web --no-web-resources-cdn
python -m http.server 8081 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8081`, finish a path assessment, then open Circles and create an account. A separate browser profile can create a second real local account to exchange invitations and requests. No sample learners, mentors, or posts are seeded. Refresh shows other accounts' latest activity.

SQLite stores account and community data in the ignored `.data/circles.sqlite3` file. Passwords are salted and hashed, sessions use expiring bearer tokens, and authorization is checked on every community action. Circles accounts do not synchronize offline lesson progress or change course eligibility. Signing out removes cached account posting points from this device's displayed total.

See [service details](server/README.md) for endpoints, checks and hosting requirements.

## Scope

This is a local learning app with a shared local Circles service. Circles accounts, invitations, mentor requests and work posts are real records shared between users of that service on this computer. Cross-device access requires a hosted service. The API binds only to loopback and is not an internet deployment. Supabase, cloud lesson sync, recruiter access, AI assistance, speech and notifications are not connected. Device learning progress is removed when app storage is cleared; community records remain in the service database.

All lesson packs ship inside the app, so lesson reading requires no connection after installation. A Flutter web build needs an initial connection; offline website installation is not configured. Circles requires its service to be running. No analytics are implemented.

## Checks

```sh
flutter analyze
flutter test
flutter build web
python -m unittest discover -s server/tests -v
```

Tests cover content integrity across all six languages, translation catalogue completeness and placeholders, immediate language changes, saved drafts and progress, lesson validation, mobile layout, assessment and taster flows, library access, and matched-course restrictions. Community tests cover consent-based invitations, private mentoring, post ownership and visibility, edit/delete points, duplicate and concurrent award limits, session expiry, and Flutter publishing-to-Progress integration.

## Source attribution

Lesson content is copied from the supplied upstream repository's `public/lessons` directory; lesson order comes from `src/lib/course-outline.ts`, at commit `df30bbc2570f4b80ee18729a154fd5508a601dd3`. Original content and branding remain attributable to that project. The source snapshot is available locally in the ignored `website-source` directory. No upstream licence file was supplied; confirm redistribution rights before public distribution.
