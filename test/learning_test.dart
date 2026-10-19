import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathmap_learn/main.dart';
import 'package:pathmap_learn/assessment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<LearningStore> createStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = LearningStore(
      await SharedPreferences.getInstance(),
      jsonDecode(await rootBundle.loadString('assets/outline.json'))
          as Map<String, dynamic>,
      jsonDecode(await rootBundle.loadString('assets/lessons/en.json'))
          as Map<String, dynamic>,
    );
    await store.initializeLanguages();
    return store;
  }

  Future<void> matchStore(LearningStore store, String path) async {
    await store.enroll(
      PathAssessment(
        ratings: {for (final p in assessmentPaths) p: p == path ? 3 : 1},
        answers: {for (final p in assessmentPaths) p: true},
        path: path,
      ),
    );
    for (var round = 0; round < 3; round++) {
      final lesson =
          store.lessons[store.ids(path)[round + 1]] as Map<String, dynamic>;
      await store.playTasterRound(path, round, lesson['answer'] as bool);
    }
    await store.saveTasterDraft(
      path,
      'My hands-on taster attempt explains the example.',
    );
    await store.rateTaster(path, 'love');
  }

  testWidgets(
    'Learning Library shows every course and can search by translated name',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(createStore))!;
      await tester.pumpWidget(PathMapApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Learning Library'));
      await tester.pumpAndSettle();
      for (final path in names.keys) {
        expect(find.byKey(ValueKey('library-$path')), findsOneWidget);
        expect(find.text(names[path]!), findsOneWidget);
      }
      expect(find.text('10 courses · 100 lessons'), findsOneWidget);
      expect(store.path, isNull);
      await store.setLanguage('fr');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cybersécurité');
      await tester.pumpAndSettle();
      expect(find.text('Cybersécurité'), findsOneWidget);
      expect(find.byKey(const ValueKey('library-web')), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzzzzz');
      await tester.pumpAndSettle();
      expect(
        find.text(store.translate('No paths found. Try another search.')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Library previews outlines without unlocking an unmatched course',
    (tester) async {
      final store = (await tester.runAsync(createStore))!;
      await matchStore(store, 'web');
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryCoursePage(store: store, path: 'data'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Course outline'), findsOneWidget);
      expect(
        find.text(store.lessons['data']['title'] as String),
        findsOneWidget,
      );
      expect(find.text(store.lessons['data']['body'] as String), findsNothing);
      expect(find.text('Quiz match needed'), findsOneWidget);
      expect(store.path, 'web');
      expect(store.canAccessCourse('data'), isFalse);
    },
  );
  testWidgets('Library fits a phone and opens the confirmed matched course', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(createStore))!;
    await matchStore(store, 'web');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryCoursePage(store: store, path: 'web'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Available to learn'), findsOneWidget);
    await tester.ensureVisible(find.text('Return to learning'));
    await tester.tap(find.text('Return to learning'));
    await tester.pumpAndSettle();
    expect(find.byType(CoursePage), findsOneWidget);
  });
  test('Every course has ten complete lessons in every language', () async {
    final store = await createStore();
    expect(store.outline.length, 10);
    for (final locale in languages.keys) {
      await store.setLanguage(locale);
      for (final path in names.keys) {
        expect(store.ids(path).length, 10);
        for (final id in store.ids(path)) {
          final lesson = store.lessons[id] as Map<String, dynamic>;
          for (final key in ['title', 'body', 'practice', 'statement']) {
            expect(
              (lesson[key] as String).trim(),
              isNotEmpty,
              reason: '$locale/$id/$key',
            );
          }
          expect(lesson['answer'], isA<bool>());
        }
      }
    }
  });
  test(
    'Every UI catalogue has complete keys and matching placeholders',
    () async {
      final store = await createStore();
      final english = store.translations['en']!;
      final placeholders = RegExp(r'\{\w+\}');
      for (final locale in languages.keys) {
        final catalog = store.translations[locale]!;
        expect(catalog.keys.toSet(), english.keys.toSet(), reason: locale);
        for (final key in english.keys) {
          expect(
            (catalog[key] as String).trim(),
            isNotEmpty,
            reason: '$locale/$key',
          );
          expect(
            placeholders
                .allMatches(catalog[key] as String)
                .map((m) => m[0])
                .toSet(),
            placeholders
                .allMatches(english[key] as String)
                .map((m) => m[0])
                .toSet(),
            reason: '$locale/$key',
          );
        }
      }
    },
  );
  testWidgets(
    'Language selection immediately updates navigation and settings',
    (tester) async {
      final store = (await tester.runAsync(createStore))!;
      await matchStore(store, 'web');
      await tester.pumpWidget(PathMapApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français').last);
      await tester.pumpAndSettle();
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Langue de l’application'), findsOneWidget);
      expect(find.text('Votre apprentissage, à votre façon.'), findsOneWidget);
      expect(find.text('App language'), findsNothing);
      expect(store.prefs.getString('language'), 'fr');
      await tester.tap(find.text('Mon cours'));
      await tester.pumpAndSettle();
      expect(find.text('Développement web'), findsOneWidget);
      await tester.tap(find.text('Développement web'));
      await tester.pumpAndSettle();
      expect(find.text('Build your first HTML page'), findsNothing);
      expect(
        find.text(store.lessons['html']['title'] as String),
        findsOneWidget,
      );
    },
  );
  testWidgets('Open lesson changes language without losing a practice draft', (
    tester,
  ) async {
    final store = (await tester.runAsync(createStore))!;
    await matchStore(store, 'web');
    await store.saveDraft(
      'html',
      'My existing practice draft stays in my own words.',
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: store,
        builder: (_, _) => MaterialApp(
          builder: (_, child) => LearningScope(store: store, child: child!),
          home: LessonPage(store: store, id: 'html'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your learning space'), findsOneWidget);
    final save = store.setLanguage('fr');
    // Preloaded packs and UI switch before asynchronous preference storage finishes.
    expect(store.language, 'fr');
    expect(store.lessons['html']['title'], isNot('Build your first HTML page'));
    await save;
    await tester.pumpAndSettle();
    expect(find.text('Votre espace d’apprentissage'), findsOneWidget);
    expect(
      store.draft('html'),
      'My existing practice draft stays in my own words.',
    );
  });
  test(
    'Drafts, selected path and unique completions survive a new store',
    () async {
      final store = await createStore();
      await matchStore(store, 'web');
      await store.saveDraft(
        'html',
        'My practice explains HTML page structure.',
      );
      await store.complete('html');
      await store.complete('html');
      final restored = LearningStore(store.prefs, store.outline, store.lessons);
      expect(restored.path, 'web');
      expect(restored.draft('html'), contains('HTML'));
      expect(restored.completed, {'html'});
      expect(restored.streak, 1);
    },
  );
  testWidgets('Lesson requires practice and correct knowledge check', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(createStore))!;
    await matchStore(store, 'web');
    await tester.pumpWidget(
      MaterialApp(
        home: LessonPage(store: store, id: 'html'),
      ),
    );
    final complete = find.widgetWithText(FilledButton, 'Complete lesson');
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pump();
    expect(
      find.text('Add at least 20 characters of practice before completing.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField),
      'HTML gives a web page its structure.',
    );
    await tester.ensureVisible(find.text('False'));
    await tester.tap(find.text('False'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pump();
    expect(store.completed, isEmpty);
    expect(
      find.text('Take another look at the lesson and try again.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('True'));
    await tester.tap(find.text('True'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(store.completed, {'html'});
  });
  testWidgets('Home fits a small phone and only shows the matched course', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(createStore))!;
    await matchStore(store, 'web');
    await tester.pumpWidget(PathMapApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My course').last);
    await tester.pumpAndSettle();
    expect(find.text('Web development'), findsOneWidget);
    expect(find.text('Cybersecurity'), findsNothing);
    expect(find.text('UI / UX design'), findsNothing);
  });
  testWidgets(
    'Activities require an attempt before interest rating and unlock one course',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(createStore))!;
      await tester.pumpWidget(MaterialApp(home: QuizPage(store: store)));
      expect(find.text('I would love this'), findsNothing);
      for (final path in assessmentPaths) {
        await tester.tap(find.byKey(ValueKey('trial-$path-true')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(path == 'web' ? 'I would love this' : 'I am curious'),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Your strongest interest'), findsOneWidget);
      expect(find.text('Web development'), findsOneWidget);
      expect(store.path, isNull);
      await tester.tap(find.text("I've found my path"));
      await tester.pumpAndSettle();
      expect(store.path, 'web');
      expect(store.canAccessCourse('data'), isFalse);
      expect(find.text('Start my taster game'), findsOneWidget);
      expect(store.canAccessCourse('web'), isFalse);
    },
  );
  test(
    'No interest, incomplete assessments and fabricated choices cannot enroll',
    () async {
      final store = await createStore();
      expect(store.path, isNull);
      final answers = {for (final p in assessmentPaths) p: false};
      final zeros = {for (final p in assessmentPaths) p: 0};
      expect(PathAssessment.matches(zeros), isEmpty);
      await expectLater(
        store.enroll(
          PathAssessment(ratings: zeros, answers: answers, path: 'data'),
        ),
        throwsStateError,
      );
      await expectLater(
        store.enroll(
          const PathAssessment(
            ratings: {'web': 3},
            answers: {'web': true},
            path: 'web',
          ),
        ),
        throwsStateError,
      );
      final ratings = {for (final p in assessmentPaths) p: p == 'web' ? 3 : 1};
      await expectLater(
        store.enroll(
          PathAssessment(ratings: ratings, answers: answers, path: 'data'),
        ),
        throwsStateError,
      );
      expect(store.path, isNull);
      await store.prefs.setString(
        'path',
        'data',
      ); // Old manual choices do not bypass the quiz.
      expect(store.path, isNull);
    },
  );
  test(
    'Unmatched and unknown lessons cannot save drafts or complete',
    () async {
      final store = await createStore();
      await expectLater(store.complete('html'), throwsStateError);
      await matchStore(store, 'web');
      await expectLater(
        store.saveDraft('data', 'An attempt on an unrelated course'),
        throwsStateError,
      );
      await expectLater(store.complete('data'), throwsStateError);
      await expectLater(store.complete('unknown'), throwsStateError);
      expect(store.nextLesson, 'html');
      await store.saveDraft(
        'html',
        'HTML describes the structure of a web page.',
      );
      await store.complete('html');
      expect(store.nextLesson, 'css');
      final restored = LearningStore(store.prefs, store.outline, store.lessons);
      expect(restored.nextLesson, 'css');
      expect(restored.canAccessCourse('web'), isTrue);
      expect(restored.canAccessCourse('design'), isFalse);
    },
  );
  testWidgets('Direct unmatched course and lesson routes show a gate', (
    tester,
  ) async {
    final store = (await tester.runAsync(createStore))!;
    await matchStore(store, 'web');
    await tester.pumpWidget(
      MaterialApp(
        home: CoursePage(store: store, path: 'data'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stay on your matched path'), findsOneWidget);
    expect(find.text(store.lessons['data']['title'] as String), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: LessonPage(store: store, id: 'data'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stay on your matched path'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('Returning learner resumes the next unfinished lesson', (
    tester,
  ) async {
    final store = (await tester.runAsync(createStore))!;
    await matchStore(store, 'web');
    await store.saveDraft(
      'html',
      'HTML gives a page its structure and headings.',
    );
    await store.complete('html');
    final restored = LearningStore(store.prefs, store.outline, store.lessons);
    await tester.pumpWidget(
      MaterialApp(
        home: CoursePage(store: restored, path: 'web'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return to learning'));
    await tester.pumpAndSettle();
    expect(find.text('Style a page with CSS'), findsOneWidget);
    expect(find.text('Build your first HTML page'), findsNothing);
  });
  test(
    'Quiz draft resumes and a partial retake keeps the existing course',
    () async {
      final store = await createStore();
      await matchStore(store, 'web');
      await store.saveAssessmentDraft(
        const AssessmentDraft(
          ratings: {'data': 2},
          answers: {'data': false},
          step: 1,
        ),
      );
      final restored = LearningStore(store.prefs, store.outline, store.lessons);
      expect(restored.assessmentDraft.step, 1);
      expect(restored.assessmentDraft.ratings['data'], 2);
      expect(restored.path, 'web');
    },
  );
  testWidgets('Tied interests require a choice among only the tied courses', (
    tester,
  ) async {
    final store = (await tester.runAsync(createStore))!;
    final ratings = {
      for (final p in assessmentPaths) p: ['web', 'design'].contains(p) ? 3 : 0,
    };
    await store.saveAssessmentDraft(
      AssessmentDraft(
        ratings: ratings,
        answers: {for (final p in assessmentPaths) p: false},
        step: 10,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: QuizPage(store: store)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, "I've found my path"),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Data analysis'), findsNothing);
    await tester.tap(find.text('UI / UX design'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I've found my path"));
    await tester.pumpAndSettle();
    expect(store.path, 'design');
    expect(store.canAccessCourse('web'), isFalse);
  });
  test(
    'Taster gates full learning, supports retries and keeps stars separate',
    () async {
      final store = await createStore();
      final result = PathAssessment(
        ratings: {for (final p in assessmentPaths) p: p == 'web' ? 3 : 1},
        answers: {for (final p in assessmentPaths) p: true},
        path: 'web',
      );
      await store.enroll(result);
      expect(store.path, 'web');
      expect(store.pathConfirmed, isFalse);
      expect(store.canAccessCourse('web'), isFalse);
      await expectLater(
        store.saveDraft('html', 'A full course draft before confirmation'),
        throwsStateError,
      );
      await expectLater(store.complete('html'), throwsStateError);
      await expectLater(store.rateTaster('web', 'love'), throwsStateError);
      await expectLater(
        store.playTasterRound('data', 0, true),
        throwsStateError,
      );
      await expectLater(
        store.playTasterRound('web', 2, true),
        throwsStateError,
      );
      for (var round = 0; round < 3; round++) {
        final answer =
            store.lessons[store.ids('web')[round + 1]]['answer'] as bool;
        expect(await store.playTasterRound('web', round, !answer), isFalse);
        expect(store.taster.stars, round);
        expect(await store.playTasterRound('web', round, answer), isTrue);
      }
      expect(store.completed, isEmpty);
      expect(store.streak, 0);
      await expectLater(store.rateTaster('web', 'love'), throwsStateError);
      await store.saveTasterDraft(
        'web',
        'I tried the example and changed how the page works.',
      );
      await store.rateTaster('web', 'unsure');
      expect(store.pathConfirmed, isFalse);
      await store.rateTaster('web', 'no');
      expect(store.pathConfirmed, isFalse);
      await store.rateTaster('web', 'love');
      expect(store.canAccessCourse('web'), isTrue);
      expect(store.canAccessCourse('data'), isFalse);
      final restored = LearningStore(store.prefs, store.outline, store.lessons);
      expect(restored.pathConfirmed, isTrue);
      expect(restored.taster.stars, 3);
      expect(restored.taster.draft, contains('changed'));
      await store.enroll(result);
      expect(
        store.pathConfirmed,
        isFalse,
        reason:
            'An accepted new assessment requires its own taster confirmation',
      );
      expect(store.taster.stars, 0);
    },
  );
  test('Partial taster resumes with its draft and can be replayed', () async {
    final store = await createStore();
    await store.enroll(
      PathAssessment(
        ratings: {for (final p in assessmentPaths) p: p == 'design' ? 3 : 0},
        answers: {for (final p in assessmentPaths) p: true},
        path: 'design',
      ),
    );
    final answer = store.lessons[store.ids('design')[1]]['answer'] as bool;
    await store.playTasterRound('design', 0, answer);
    await store.saveTasterDraft(
      'design',
      'I am exploring an early design idea.',
    );
    final restored = LearningStore(store.prefs, store.outline, store.lessons);
    expect(restored.taster.stars, 1);
    expect(restored.taster.draft, contains('design idea'));
    expect(restored.pathConfirmed, isFalse);
    await restored.replayTaster('design');
    expect(restored.taster.stars, 0);
    expect(restored.taster.draft, isEmpty);
  });
  testWidgets(
    'Taster game leads through practice and confirmation to the full course',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(createStore))!;
      await store.enroll(
        PathAssessment(
          ratings: {for (final p in assessmentPaths) p: p == 'web' ? 3 : 0},
          answers: {for (final p in assessmentPaths) p: true},
          path: 'web',
        ),
      );
      await tester.pumpWidget(MaterialApp(home: TasterPage(store: store)));
      expect(find.text("I've found my path"), findsOneWidget);
      await tester.tap(find.text('Start my taster game'));
      await tester.pumpAndSettle();
      for (var round = 0; round < 3; round++) {
        final answer =
            store.lessons[store.ids('web')[round + 1]]['answer'] as bool;
        await tester.tap(find.byKey(ValueKey('taster-$round-$answer')));
        await tester.pumpAndSettle();
      }
      expect(store.pathConfirmed, isFalse);
      final confirm = find.widgetWithText(FilledButton, 'Yes, this is my path');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byType(TextField),
        'I tried a button that changes a welcome message.',
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Your path is confirmed!'), findsOneWidget);
      await tester.tap(find.text('Start my full course'));
      await tester.pumpAndSettle();
      expect(find.text('Build your first HTML page'), findsOneWidget);
      expect(store.pathConfirmed, isTrue);
      expect(store.completed, isEmpty);
    },
  );
  testWidgets(
    'Pending course routes lead to taster and home celebrates a found path',
    (tester) async {
      final store = (await tester.runAsync(createStore))!;
      await store.enroll(
        PathAssessment(
          ratings: {for (final p in assessmentPaths) p: p == 'data' ? 3 : 0},
          answers: {for (final p in assessmentPaths) p: false},
          path: 'data',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CoursePage(store: store, path: 'data'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Taste your path first'), findsOneWidget);
      expect(find.text('Return to learning'), findsNothing);
      await tester.pumpWidget(PathMapApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text("I've found my path"), findsOneWidget);
      expect(find.text('Try my taster'), findsOneWidget);
    },
  );
}
