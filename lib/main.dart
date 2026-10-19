import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'assessment.dart';
import 'taster_progress.dart';
import 'community_store.dart';
part 'quiz_page.dart';
part 'taster_page.dart';
part 'library_page.dart';
part 'circles_page.dart';

const green = Color(0xFF194C3A);
const amber = Color(0xFFE8B750);
const names = <String, String>{
  'data': 'Data analysis',
  'web': 'Web development',
  'cyber': 'Cybersecurity',
  'ai': 'AI & machine learning',
  'design': 'UI / UX design',
  'marketing': 'Digital marketing',
  'business': 'Business & entrepreneurship',
  'writing': 'Writing & communication',
  'project': 'Project management',
  'teaching': 'Teaching & facilitation',
};
const icons = <String, IconData>{
  'data': Icons.bar_chart_rounded,
  'web': Icons.code_rounded,
  'cyber': Icons.shield_outlined,
  'ai': Icons.auto_awesome,
  'design': Icons.palette_outlined,
  'marketing': Icons.campaign_outlined,
  'business': Icons.storefront_outlined,
  'writing': Icons.edit_note,
  'project': Icons.account_tree_outlined,
  'teaching': Icons.school_outlined,
};
const languages = {
  'en': 'English',
  'pcm': 'Naijá (Pidgin)',
  'yo': 'Yorùbá',
  'ha': 'Hausa',
  'ig': 'Igbo',
  'fr': 'Français',
};

class LearningStore extends ChangeNotifier {
  LearningStore(
    this.prefs,
    this.outline,
    this.lessons, {
    CommunityStore? communityStore,
  }) {
    _language = prefs.getString('language') ?? 'en';
    _lessonPacks[_language] = lessons;
    community = communityStore ?? CommunityStore(prefs);
    community.addListener(notifyListeners);
  }
  final SharedPreferences prefs;
  late final CommunityStore community;
  int get totalPoints => completed.length * 20 + community.postPoints;
  final Map<String, dynamic> outline;
  Map<String, dynamic> lessons;
  late String _language;
  String get language => _language;
  final Map<String, Map<String, dynamic>> _lessonPacks = {};
  final Map<String, Map<String, dynamic>> translations = {};
  Future<void> initializeLanguages() async {
    await Future.wait(
      languages.keys.map((locale) async {
        final ui =
            jsonDecode(await rootBundle.loadString('assets/ui/$locale.json'))
                as Map<String, dynamic>;
        final pack =
            jsonDecode(
                  await rootBundle.loadString('assets/lessons/$locale.json'),
                )
                as Map<String, dynamic>;
        translations[locale] = ui;
        _lessonPacks[locale] = pack;
      }),
    );
    notifyListeners();
  }

  String translate(String text, [Map<String, String> values = const {}]) {
    var translated = translations[language]?[text] as String? ?? text;
    for (final entry in values.entries) {
      translated = translated.replaceAll('{${entry.key}}', entry.value);
    }
    return translated;
  }

  PathAssessment? get assessment =>
      PathAssessment.read(prefs.getString('assessment'));
  String? get path => assessment?.path;
  TasterProgress get taster => TasterProgress.read(
    prefs.getString('taster'),
    prefs.getString('assessment'),
  );
  bool get pathConfirmed => path != null && taster.confirmed;
  String get learningAction =>
      pathConfirmed ? 'Return to learning' : 'Try my taster';
  AssessmentDraft get assessmentDraft =>
      AssessmentDraft.read(prefs.getString('assessment_draft'));
  bool canAccessCourse(String course) =>
      names.containsKey(course) && path == course && pathConfirmed;
  bool canAccessLesson(String id) => pathConfirmed && ids(path!).contains(id);
  String? get nextLesson {
    if (!pathConfirmed) return null;
    final course = ids(path!);
    return course.firstWhere(
      (id) => !completed.contains(id),
      orElse: () => course.first,
    );
  }

  Future<void> saveAssessmentDraft(AssessmentDraft draft) async {
    if (!await prefs.setString('assessment_draft', draft.encode())) {
      throw StateError('Could not save quiz');
    }
  }

  Future<void> enroll(PathAssessment result) async {
    if (PathAssessment.read(result.encode()) == null) {
      throw StateError('Complete the assessment first');
    }
    final record = jsonDecode(result.encode()) as Map<String, dynamic>;
    record['attempt'] = DateTime.now().microsecondsSinceEpoch.toString();
    if (!await prefs.setString('assessment', jsonEncode(record))) {
      throw StateError('Could not save match');
    }
    await prefs.remove('assessment_draft');
    notifyListeners();
  }

  void _requireTasterPath(String course) {
    if (path != course || !names.containsKey(course)) {
      throw StateError('Choose your matched path first');
    }
  }

  Future<void> _saveTaster(TasterProgress progress) async {
    final signature = prefs.getString('assessment');
    if (signature == null || path == null) throw StateError('No matched path');
    if (!await prefs.setString('taster', progress.encode(signature))) {
      throw StateError('Could not save taster');
    }
    notifyListeners();
  }

  Future<bool> playTasterRound(String course, int round, bool answer) async {
    _requireTasterPath(course);
    if (round != taster.stars || round < 0 || round >= 3) {
      throw StateError('Play the next round');
    }
    final lesson = lessons[ids(course)[round + 1]] as Map<String, dynamic>;
    if (lesson['answer'] != answer) return false;
    await _saveTaster(TasterProgress(stars: round + 1, draft: taster.draft));
    return true;
  }

  Future<void> saveTasterDraft(String course, String draft) async {
    _requireTasterPath(course);
    await _saveTaster(
      TasterProgress(
        stars: taster.stars,
        draft: draft,
        rating: draft == taster.draft ? taster.rating : null,
      ),
    );
  }

  Future<void> rateTaster(String course, String rating) async {
    _requireTasterPath(course);
    if (!taster.ready || !['love', 'unsure', 'no'].contains(rating)) {
      throw StateError('Finish the taster first');
    }
    await _saveTaster(
      TasterProgress(stars: taster.stars, draft: taster.draft, rating: rating),
    );
  }

  Future<void> replayTaster(String course) async {
    _requireTasterPath(course);
    await _saveTaster(const TasterProgress());
  }

  bool get dark => prefs.getBool('dark') ?? false;
  Set<String> get completed => (prefs.getStringList('completed') ?? []).toSet();
  List<String> ids(String path) => List<String>.from(outline[path] as List);
  String draft(String id) => prefs.getString('draft:$id') ?? '';
  Future<void> saveDraft(String id, String value) async {
    if (!canAccessLesson(id)) {
      throw StateError('This lesson is not in your matched course');
    }
    await prefs.setString('draft:$id', value);
  }

  Future<void> setDark(bool value) async {
    await prefs.setBool('dark', value);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    if (!languages.containsKey(value)) {
      throw ArgumentError.value(value, 'language');
    }
    if (!translations.containsKey(value)) await initializeLanguages();
    final previous = language;
    _language = value;
    lessons = _lessonPacks[value]!;
    notifyListeners();
    try {
      if (!await prefs.setString('language', value)) {
        throw StateError('Language could not be saved');
      }
    } catch (_) {
      if (language == value) {
        _language = previous;
        lessons = _lessonPacks[previous]!;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> complete(String id) async {
    if (!canAccessLesson(id)) {
      throw StateError('This lesson is not in your matched course');
    }
    await prefs.setStringList('completed', {...completed, id}.toList());
    final now = DateTime.now().toUtc().add(const Duration(hours: 1));
    final day = now.toIso8601String().substring(0, 10);
    await prefs.setStringList(
      'days',
      {...?prefs.getStringList('days'), day}.toList(),
    );
    notifyListeners();
  }

  int get streak {
    final days = (prefs.getStringList('days') ?? []).toSet();
    var date = DateTime.now().toUtc().add(const Duration(hours: 1));
    if (!days.contains(date.toIso8601String().substring(0, 10))) {
      date = date.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (days.contains(date.toIso8601String().substring(0, 10))) {
      count++;
      date = date.subtract(const Duration(days: 1));
    }
    return count;
  }

  @override
  void dispose() {
    community.removeListener(notifyListeners);
    community.dispose();
    super.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    final outline =
        jsonDecode(await rootBundle.loadString('assets/outline.json'))
            as Map<String, dynamic>;
    final locale = prefs.getString('language') ?? 'en';
    final lessons =
        jsonDecode(await rootBundle.loadString('assets/lessons/$locale.json'))
            as Map<String, dynamic>;
    final store = LearningStore(prefs, outline, lessons);
    await store.initializeLanguages();
    runApp(PathMapApp(store: store));
    if (store.community.signedIn) unawaited(store.community.refresh());
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Could not load your learning space. Please restart the app.',
            ),
          ),
        ),
      ),
    );
  }
}

class PathMapApp extends StatelessWidget {
  const PathMapApp({super.key, required this.store});
  final LearningStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'PathMap Learn',
      debugShowCheckedModeBanner: false,
      themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: Locale(store.language == 'fr' ? 'fr' : 'en'),
      supportedLocales: const [Locale('en'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => LearningScope(store: store, child: child!),
      home: Home(store: store),
    ),
  );
  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      brightness: brightness,
      secondary: amber,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFFAF9F5)
        : const Color(0xFF121C17),
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class LearningScope extends InheritedNotifier<LearningStore> {
  const LearningScope({
    super.key,
    required LearningStore store,
    required super.child,
  }) : super(notifier: store);
}

String t(
  BuildContext context,
  String text, [
  Map<String, String> values = const {},
]) {
  final store = context
      .dependOnInheritedWidgetOfExactType<LearningScope>()
      ?.notifier;
  if (store != null) return store.translate(text, values);
  var result = text;
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', entry.value);
  }
  return result;
}

Widget learningDestination(LearningStore store) => store.path == null
    ? QuizPage(store: store)
    : store.pathConfirmed
    ? CoursePage(store: store, path: store.path!)
    : TasterPage(store: store);

class Home extends StatefulWidget {
  const Home({super.key, required this.store});
  final LearningStore store;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  LearningStore get s => widget.store;
  void openPath(String path) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => path == s.path
          ? learningDestination(s)
          : CoursePage(store: s, path: path),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, color: green),
            SizedBox(width: 8),
            Text('PathMap', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(' Learn', style: TextStyle(fontWeight: FontWeight.w300)),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: t(context, 'Learning Library'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LearningLibraryPage(store: s),
            ),
          ),
          icon: const Icon(Icons.local_library_outlined),
        ),
        IconButton(
          tooltip: t(context, 'Settings'),
          onPressed: () => setState(() => tab = 4),
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) =>
              ListView(padding: const EdgeInsets.all(24), children: content()),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) {
        setState(() => tab = v);
        if (v == 2 && s.community.signedIn) unawaited(s.community.refresh());
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: t(context, 'Home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.explore_outlined),
          label: t(context, 'My course'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.insights_outlined),
          label: t(context, 'Progress'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.people_outline),
          label: t(context, 'Circles'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          label: t(context, 'You'),
        ),
      ],
    ),
  );
  List<Widget> content() {
    switch (tab) {
      case 1:
        return [
          heading(
            t(context, 'My course'),
            t(context, 'Your matched course, your saved work, your next step.'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LearningLibraryPage(store: s),
              ),
            ),
            icon: const Icon(Icons.local_library_outlined),
            label: Text(t(context, 'Browse Learning Library')),
          ),
          const SizedBox(height: 16),
          if (s.path != null)
            courseCard(s.path!)
          else
            CourseGate(store: s, embedded: true),
          if (s.path != null)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => TasterPage(store: s)),
              ),
              icon: const Icon(Icons.sports_esports_outlined),
              label: Text(t(context, 'Taster')),
            ),
          if (s.path != null)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => QuizPage(store: s)),
              ),
              child: Text(t(context, 'Retake quiz')),
            ),
        ];
      case 2:
        return [
          heading(
            t(context, 'Small steps. Real progress.'),
            t(context, 'Your learning activity on this device.'),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(
                '${s.completed.length}',
                t(context, 'Lessons completed'),
                Icons.task_alt,
              ),
              metric(
                '${s.totalPoints}',
                t(context, 'Learning points'),
                Icons.stars_outlined,
              ),
              metric(
                '${s.streak}',
                t(context, 'Day streak'),
                Icons.local_fire_department_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          metric(
            '${s.community.postPoints}',
            t(context, 'Posting points'),
            Icons.forum_outlined,
          ),
          const SizedBox(height: 12),
          Text(
            t(
              context,
              'Posts earn 10 points each, up to 30 per day. Edits earn no extra points. Deleted posts lose their points; reposts do not earn again.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              context,
              'Lesson points stay on this device. Posting points belong to your signed-in Circles account.',
            ),
          ),
          const SizedBox(height: 24),
          if (s.path != null) courseCard(s.path!),
          if (s.completed.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t(
                  context,
                  'Your first step starts a new story. Complete a lesson to see your progress here.',
                ),
              ),
            ),
        ];
      case 3:
        return [CirclesPanel(store: s)];
      case 4:
        return [
          heading(
            t(context, 'Your learning, your way.'),
            t(context, 'Preferences are saved on this device.'),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(context, 'App language'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(s.language),
                    initialValue: s.language,
                    items: languages.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      if (v != null) {
                        try {
                          await s.setLanguage(v);
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  t(
                                    context,
                                    'Could not load that language. Try again.',
                                  ),
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      context,
                      'The whole app and lessons use your selected language.',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t(context, 'Dark appearance')),
                    value: s.dark,
                    onChanged: s.setDark,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.offline_bolt_outlined),
                    title: Text(t(context, 'Ready for offline learning')),
                    subtitle: Text(
                      t(
                        context,
                        'All six lesson packs are included. No account needed.',
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: Text(t(context, 'Your progress stays here')),
                    subtitle: Text(
                      t(
                        context,
                        'Practice drafts and progress are stored on this device. Clearing app data removes them.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      default:
        return [
          Text(
            t(context, 'A LITTLE CURIOSITY. A NEW DIRECTION.'),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: green,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(
                  label: Text(
                    t(
                      context,
                      s.path == null
                          ? 'Made for your next step'
                          : "I've found my path",
                    ),
                  ),
                  avatar: const Icon(Icons.spa_outlined, size: 18),
                ),
                const SizedBox(height: 20),
                Text(
                  t(context, 'Your potential.\nYour path.'),
                  style: const TextStyle(
                    fontSize: 44,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t(
                    context,
                    'Build useful skills at your own pace.\nStart small. Keep going. Find what fits you.',
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: amber,
                    foregroundColor: const Color(0xFF20352D),
                  ),
                  onPressed: () => s.path == null
                      ? Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => QuizPage(store: s),
                          ),
                        )
                      : openPath(s.path!),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    t(
                      context,
                      s.path == null ? 'Find my path' : s.learningAction,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              metric(
                '10',
                t(context, 'Learning paths'),
                Icons.explore_outlined,
              ),
              metric('6', t(context, 'Lesson languages'), Icons.translate),
              metric(
                '100',
                t(context, 'Practical lessons'),
                Icons.menu_book_outlined,
              ),
            ],
          ),
          const SizedBox(height: 30),
          heading(
            t(context, 'Make a little progress today'),
            t(context, 'Pick up your path, one lesson at a time.'),
          ),
          const SizedBox(height: 16),
          if (s.path != null)
            courseCard(s.path!)
          else
            CourseGate(store: s, embedded: true),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  t(context, 'Your learning journey'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => tab = 1),
                child: Text(t(context, 'My course')),
              ),
            ],
          ),
          Text(
            t(
              context,
              'Complete the activity quiz to unlock your matched course and learn offline.',
            ),
          ),
        ];
    }
  }

  Widget courseCard(String path) {
    final ids = s.ids(path);
    final done = ids.where(s.completed.contains).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => openPath(path),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icons[path],
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(context, names[path]!),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        t(
                          context,
                          s.pathConfirmed
                              ? '{done} / {total} lessons · Beginner friendly'
                              : 'Try my taster',
                          {'done': '$done', 'total': '${ids.length}'},
                        ),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: done / ids.length,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget heading(String title, String subtitle) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      title,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
    ),
    const SizedBox(height: 8),
    Text(subtitle, style: const TextStyle(height: 1.5)),
  ],
);
Widget metric(String value, String label, IconData icon) => Container(
  width: 155,
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: amber.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22),
      const SizedBox(height: 10),
      Text(
        value,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      Text(label),
    ],
  ),
);

class CoursePage extends StatelessWidget {
  const CoursePage({super.key, required this.store, required this.path});
  final LearningStore store;
  final String path;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (!store.canAccessCourse(path)) return CourseGate(store: store);
      return Scaffold(
        appBar: AppBar(title: Text(t(context, names[path]!))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  heading(
                    t(context, 'A path worth taking.'),
                    t(context, 'Learn, practise and check your understanding.'),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            LessonPage(store: store, id: store.nextLesson!),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(t(context, 'Return to learning')),
                  ),
                  const SizedBox(height: 24),
                  ...store.ids(path).indexed.map((entry) {
                    final id = entry.$2;
                    final lesson = store.lessons[id] as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: store.completed.contains(id)
                                ? green
                                : amber.withValues(alpha: .25),
                            child: store.completed.contains(id)
                                ? const Icon(Icons.check, color: Colors.white)
                                : Text('${entry.$1 + 1}'),
                          ),
                          title: Text(lesson['title'] as String),
                          subtitle: Text(
                            store.completed.contains(id)
                                ? t(context, 'Completed · Tap to review')
                                : t(
                                    context,
                                    'Read · Practise · Knowledge check',
                                  ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LessonPage(store: store, id: id),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class LessonPage extends StatefulWidget {
  const LessonPage({super.key, required this.store, required this.id});
  final LearningStore store;
  final String id;
  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  late final TextEditingController draft;
  bool? answer;
  bool busy = false;
  String? feedback;
  @override
  void initState() {
    super.initState();
    draft = TextEditingController(text: widget.store.draft(widget.id));
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    t(
      context,
      'My course',
    ); // Observe language and enrollment changes on open routes.
    if (!widget.store.canAccessLesson(widget.id)) {
      return CourseGate(store: widget.store);
    }
    final l = widget.store.lessons[widget.id] as Map<String, dynamic>;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Your learning space'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l['title'] as String,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              SelectableText(
                l['body'] as String,
                style: const TextStyle(fontSize: 17, height: 1.8),
              ),
              if (l['code'] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SelectableText(
                        l['code'] as String,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              heading(t(context, 'Try it yourself'), l['practice'] as String),
              const SizedBox(height: 16),
              TextField(
                controller: draft,
                minLines: 5,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: t(context, 'Your practice'),
                  hintText: t(
                    context,
                    'Write at least 20 characters. Your draft saves as you type.',
                  ),
                ),
                onChanged: (v) async {
                  try {
                    await widget.store.saveDraft(widget.id, v);
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => feedback =
                            'Draft could not be saved. Please try again.',
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 28),
              heading(
                t(context, 'Check your understanding'),
                l['statement'] as String,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  for (final v in [true, false])
                    ChoiceChip(
                      label: Text(v ? t(context, 'True') : t(context, 'False')),
                      selected: answer == v,
                      onSelected: (_) => setState(() {
                        answer = v;
                        feedback = null;
                      }),
                    ),
                ],
              ),
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(t(context, feedback!)),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (draft.text.trim().runes.length < 20) {
                          setState(
                            () => feedback =
                                'Add at least 20 characters of practice before completing.',
                          );
                          return;
                        }
                        if (answer != l['answer']) {
                          setState(
                            () => feedback = answer == null
                                ? 'Choose True or False to check your understanding.'
                                : 'Take another look at the lesson and try again.',
                          );
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await widget.store.saveDraft(widget.id, draft.text);
                          await widget.store.complete(widget.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  t(
                                    context,
                                    'Lesson complete. Another step forward!',
                                  ),
                                ),
                              ),
                            );
                            Navigator.pop(context);
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(() {
                              busy = false;
                              feedback =
                                  'Could not save your progress. Please try again.';
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.task_alt),
                label: Text(
                  busy ? t(context, 'Saving…') : t(context, 'Complete lesson'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
