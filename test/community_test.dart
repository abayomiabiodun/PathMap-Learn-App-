import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathmap_learn/main.dart';
import 'package:pathmap_learn/community_store.dart';
import 'package:pathmap_learn/assessment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> shared;
  late List<http.Request> requests;
  late LearningStore store;
  Future<void> setup() async {
    SharedPreferences.setMockInitialValues({'community_token': 'test-session'});
    final prefs = await SharedPreferences.getInstance();
    shared = {
      'profile': {
        'id': 'me',
        'name': 'Test learner',
        'path': 'web',
        'discoverable': 1,
        'mentor_bio': '',
        'mentor_available': 0,
        'post_points': 0,
      },
      'own_circle': 'circle-1',
      'circles': [
        {'id': 'circle-1', 'owner_name': 'Test learner', 'own': 1},
      ],
      'members': [
        {'id': 'me', 'name': 'Test learner'},
      ],
      'learners': [
        {
          'id': 'peer',
          'name': 'Test peer',
          'path': 'web',
          'member': 0,
          'pending': 0,
        },
      ],
      'invites': [
        {
          'id': 'invite-in',
          'sender_name': 'Test inviter',
          'recipient_name': 'Test learner',
          'incoming': 1,
          'status': 'pending',
        },
      ],
      'mentors': [
        {
          'id': 'mentor',
          'name': 'Test mentor',
          'path': 'web',
          'mentor_bio':
              'A self-described volunteer who can help with test web lessons.',
        },
      ],
      'guidance': [],
      'posts': [],
    };
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(jsonEncode(shared), 200);
      }
      if (request.url.path == '/invites') shared['learners'][0]['pending'] = 1;
      if (request.url.path == '/invites/invite-in/respond') {
        shared['invites'][0]['status'] = 'accepted';
      }
      if (request.url.path == '/posts') {
        final post = jsonDecode(request.body) as Map<String, dynamic>;
        shared['profile']['post_points'] = 10;
        shared['posts'] = [
          {
            ...post,
            'id': 'post-1',
            'circle_id': 'circle-1',
            'own': 1,
            'author_name': 'Test learner',
            'circle_owner': 'Test learner',
            'points': 10,
            'created': '2026-10-19T09:00:00Z',
            'updated': '2026-10-19T09:00:00Z',
          },
        ];
      }
      if (request.method == 'DELETE') {
        shared['profile']['post_points'] = 0;
        shared['posts'] = [];
      }
      return http.Response('{"ok":true}', 200);
    });
    final community = CommunityStore(
      prefs,
      client: client,
      apiUrl: 'http://test.local',
    );
    store = LearningStore(
      prefs,
      jsonDecode(await rootBundle.loadString('assets/outline.json'))
          as Map<String, dynamic>,
      jsonDecode(await rootBundle.loadString('assets/lessons/en.json'))
          as Map<String, dynamic>,
      communityStore: community,
    );
    await store.initializeLanguages();
    await store.enroll(
      PathAssessment(
        ratings: {for (final p in assessmentPaths) p: p == 'web' ? 3 : 0},
        answers: {for (final p in assessmentPaths) p: true},
        path: 'web',
      ),
    );
    await community.refresh();
  }

  void largeScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Circle invitation buttons send authenticated consent-based requests',
    (tester) async {
      largeScreen(tester);
      await tester.runAsync(setup);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CirclesPanel(store: store)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite to my circle'));
      await tester.pumpAndSettle();
      expect(find.text('Invitation pending'), findsOneWidget);
      final invitation = requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path == '/invites',
      );
      expect(jsonDecode(invitation.body)['learner'], 'peer');
      expect(invitation.headers['Authorization'], 'Bearer test-session');
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('accepted'), findsOneWidget);
    },
  );

  testWidgets(
    'Work publishing and deletion update account points and total progress',
    (tester) async {
      largeScreen(tester);
      await tester.runAsync(setup);
      await store.prefs.setStringList('completed', ['html']);
      await tester.pumpWidget(PathMapApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Circles'));
      await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('circles-post-shortcut')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'My first useful web project',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'I built a page with clear headings and accessible labels, then tested it on my phone.',
      );
      await tester.tap(find.text('Share with my circle'));
      await tester.pumpAndSettle();
      expect(find.text('My first useful web project'), findsOneWidget);
      expect(find.text('Edit post'), findsOneWidget);
      expect(store.community.postPoints, 10);
      expect(store.totalPoints, 30);
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this post?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('My first useful web project'), findsNothing);
      expect(store.community.postPoints, 0);
      expect(store.totalPoints, 20);
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(find.text('Posting points'), findsOneWidget);
    },
  );

  testWidgets('Mentoring form sends the selected mentor a private request', (
    tester,
  ) async {
    largeScreen(tester);
    await tester.runAsync(setup);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CirclesPanel(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('circles-mentor-shortcut')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request mentoring'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Could you help me understand semantic headings in my first HTML page?',
    );
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    final request = requests.lastWhere((r) => r.url.path == '/guidance');
    expect(jsonDecode(request.body)['mentor'], 'mentor');
    expect(jsonDecode(request.body)['message'], contains('semantic headings'));
  });

  test('Expired account sessions clear cached posting points', () async {
    SharedPreferences.setMockInitialValues({
      'community_token': 'expired',
      'community_points': 30,
    });
    final community = CommunityStore(
      await SharedPreferences.getInstance(),
      apiUrl: 'http://test.local',
      client: MockClient(
        (_) async => http.Response(
          '{"error":"Your session expired. Please sign in again."}',
          401,
        ),
      ),
    );
    expect(community.postPoints, 30);
    await community.refresh();
    expect(community.signedIn, isFalse);
    expect(community.postPoints, 0);
    expect(community.error, contains('session expired'));
  });
  test('Successful post is not retried when only its refresh fails', () async {
    SharedPreferences.setMockInitialValues({'community_token': 'test-session'});
    var writes = 0;
    final community = CommunityStore(
      await SharedPreferences.getInstance(),
      apiUrl: 'http://test.local',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          writes++;
          return http.Response('{"id":"created"}', 200);
        }
        throw Exception('offline after saving');
      }),
    );
    await community.act('POST', '/posts', {'title': 'Test'});
    expect(writes, 1);
    expect(community.error, 'Saved, but refresh failed. Tap Refresh.');
  });
}
