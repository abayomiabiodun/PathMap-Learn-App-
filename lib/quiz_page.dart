part of 'main.dart';

class CourseGate extends StatelessWidget {
  const CourseGate({super.key, required this.store, this.embedded = false});
  final LearningStore store;
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 36, color: green),
        const SizedBox(height: 16),
        heading(
          t(
            context,
            store.path == null
                ? 'Discover your course first'
                : !store.pathConfirmed
                ? 'Taste your path first'
                : 'Stay on your matched path',
          ),
          t(
            context,
            store.path == null
                ? 'Try ten course activities, discover what you enjoy, and unlock one course.'
                : !store.pathConfirmed
                ? 'Play your matched taster and confirm your interest before opening the full course.'
                : 'Only your quiz-matched course is available for learning. Retake the quiz to find a new match.',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => store.path == null
                  ? QuizPage(store: store)
                  : learningDestination(store),
            ),
          ),
          icon: const Icon(Icons.arrow_forward),
          label: Text(
            t(
              context,
              store.path == null ? 'Find my path' : store.learningAction,
            ),
          ),
        ),
      ],
    );
    if (embedded) {
      return Card(
        child: Padding(padding: const EdgeInsets.all(24), child: content),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'My course'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: content,
          ),
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.store});
  final LearningStore store;
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late Map<String, int> ratings;
  late Map<String, bool> answers;
  late int step;
  String? selectedMatch;
  String? error;
  bool busy = false;
  final scroll = ScrollController();
  LearningStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final draft = store.assessmentDraft;
    ratings = {...draft.ratings};
    answers = {...draft.answers};
    step = draft.step;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> update({
    int? nextStep,
    String? path,
    bool? answer,
    int? rating,
    bool restart = false,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final nextRatings = restart ? <String, int>{} : {...ratings};
    final nextAnswers = restart ? <String, bool>{} : {...answers};
    if (path != null && answer != null) nextAnswers[path] = answer;
    if (path != null && rating != null) nextRatings[path] = rating;
    try {
      await store.saveAssessmentDraft(
        AssessmentDraft(
          ratings: nextRatings,
          answers: nextAnswers,
          step: restart ? 0 : nextStep ?? step,
        ),
      );
      if (!mounted) return;
      setState(() {
        ratings = nextRatings;
        answers = nextAnswers;
        step = restart ? 0 : nextStep ?? step;
        selectedMatch = null;
        busy = false;
      });
      if ((nextStep != null || restart) && scroll.hasClients) scroll.jumpTo(0);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save your quiz. Please try again.';
        });
      }
    }
  }

  Future<void> startCourse(String path) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await store.enroll(
        PathAssessment(ratings: ratings, answers: answers, path: path),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => TasterPage(store: store)),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save your quiz. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = step == assessmentPaths.length;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Find my path'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(24),
            children: [
              LinearProgressIndicator(
                value: step / assessmentPaths.length,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 24),
              if (result)
                ...results(context)
              else
                ...activity(context, assessmentPaths[step]),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    t(context, error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> activity(BuildContext context, String path) {
    final lesson = store.lessons[store.ids(path).first] as Map<String, dynamic>;
    final attempted = answers.containsKey(path);
    final correct = answers[path] == lesson['answer'];
    return [
      Text(
        t(context, 'QUESTION {current} OF {total}', {
          'current': '${step + 1}',
          'total': '${assessmentPaths.length}',
        }),
        style: const TextStyle(letterSpacing: 1.4),
      ),
      const SizedBox(height: 12),
      heading(
        t(context, names[path]!),
        t(
          context,
          'Try the activity, then tell us how it felt. Your interest decides your match, not your score.',
        ),
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icons[path]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lesson['title'] as String,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                lesson['body'] as String,
                style: const TextStyle(height: 1.6),
              ),
              if (lesson['code'] != null)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(t(context, 'Explore the example')),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SelectableText(
                        lesson['code'] as String,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              const Divider(height: 28),
              Text(
                t(context, 'Check your understanding'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                lesson['statement'] as String,
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  for (final answer in [true, false])
                    ChoiceChip(
                      key: ValueKey('trial-$path-$answer'),
                      label: Text(t(context, answer ? 'True' : 'False')),
                      selected: attempted && answers[path] == answer,
                      onSelected: busy
                          ? null
                          : (_) => update(path: path, answer: answer),
                    ),
                ],
              ),
              if (attempted)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      t(
                        context,
                        correct
                            ? 'You got it! Now think about whether you enjoyed this activity.'
                            : 'Good try. The correct answer is {answer}. You can still enjoy this subject as a beginner.',
                        {
                          'answer': t(
                            context,
                            lesson['answer'] == true ? 'True' : 'False',
                          ),
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (attempted) ...[
        heading(
          t(context, 'How did this activity feel?'),
          t(
            context,
            'Would you like to learn more and practise this kind of work?',
          ),
        ),
        const SizedBox(height: 16),
        for (final choice in [
          ('I would love this', 3),
          ('I am interested', 2),
          ('I am curious', 1),
          ('Not for me', 0),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => update(
                      path: path,
                      rating: choice.$2,
                      nextStep: step + 1,
                    ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(t(context, choice.$1)),
            ),
          ),
      ] else
        Text(
          t(
            context,
            'Choose True or False to try the activity before rating your interest.',
          ),
        ),
      if (step > 0)
        TextButton(
          onPressed: busy ? null : () => update(nextStep: step - 1),
          child: Text(t(context, 'Previous question')),
        ),
      if (store.path != null)
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => learningDestination(store),
                  ),
                ),
          child: Text(t(context, store.learningAction)),
        ),
    ];
  }

  List<Widget> results(BuildContext context) {
    final matches = PathAssessment.matches(ratings);
    final match = matches.length == 1 ? matches.first : selectedMatch;
    return [
      Text(
        t(context, 'YOUR NEXT CHAPTER'),
        style: const TextStyle(letterSpacing: 1.4),
      ),
      const SizedBox(height: 20),
      heading(
        t(
          context,
          matches.isEmpty ? 'Keep exploring' : 'Your strongest interest',
        ),
        t(
          context,
          matches.isEmpty
              ? 'No activity sparked an interest yet. Try the quiz again; no course has been assigned.'
              : matches.length > 1
              ? 'These activities interested you equally. Choose one of your tied matches to focus on.'
              : 'Your favourite activity points to this course. Start here and build your skills step by step.',
        ),
      ),
      const SizedBox(height: 20),
      if (matches.length == 1)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            leading: Icon(icons[match], color: green),
            title: Text(t(context, names[match]!)),
            subtitle: Text(
              t(
                context,
                'First try a taster to confirm this path. Then unlock its full course.',
              ),
            ),
          ),
        ),
      if (matches.length > 1)
        ...matches.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => setState(() => selectedMatch = p),
              icon: Icon(
                selectedMatch == p
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              label: Text(t(context, names[p]!)),
            ),
          ),
        ),
      if (matches.isNotEmpty) ...[
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy || match == null ? null : () => startCourse(match),
          icon: const Icon(Icons.arrow_forward),
          label: Text(t(context, "I've found my path")),
        ),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: busy
            ? null
            : () => update(nextStep: assessmentPaths.length - 1),
        child: Text(t(context, 'Review my answers')),
      ),
      TextButton(
        onPressed: busy ? null : () => update(restart: true),
        child: Text(t(context, 'Retake quiz')),
      ),
      if (store.path != null)
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => learningDestination(store),
                  ),
                ),
          child: Text(t(context, store.learningAction)),
        ),
    ];
  }
}
