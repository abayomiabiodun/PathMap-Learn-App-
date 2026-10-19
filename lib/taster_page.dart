part of 'main.dart';

class TasterPage extends StatefulWidget {
  const TasterPage({super.key, required this.store});
  final LearningStore store;
  @override
  State<TasterPage> createState() => _TasterPageState();
}

class _TasterPageState extends State<TasterPage> {
  late final TextEditingController practice;
  late final String? assessmentSignature;
  bool started = false;
  bool busy = false;
  String? feedback;
  LearningStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    practice = TextEditingController(text: store.taster.draft);
    assessmentSignature = store.prefs.getString('assessment');
    started = store.taster.stars > 0;
  }

  @override
  void dispose() {
    practice.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) feedback = 'Could not save your taster. Please try again.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> answer(bool value) => run(() async {
    final correct = await store.playTasterRound(
      store.path!,
      store.taster.stars,
      value,
    );
    if (mounted) {
      feedback = correct
          ? 'Star earned! Your next challenge is ready.'
          : 'Not quite. Look at the clue and try again. You can retry as often as you like.';
    }
  });

  Future<void> rate(String value) => run(() async {
    await store.saveTasterDraft(store.path!, practice.text);
    await store.rateTaster(store.path!, value);
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (store.path == null ||
          assessmentSignature != store.prefs.getString('assessment')) {
        return CourseGate(store: store);
      }
      final path = store.path!;
      final progress = store.taster;
      final round = progress.stars;
      final lesson =
          store.lessons[store.ids(path)[round < 3 ? round + 1 : 2]]
              as Map<String, dynamic>;
      return Scaffold(
        appBar: AppBar(title: Text(t(context, 'Taster'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Chip(
                  avatar: const Icon(Icons.explore_outlined, size: 20),
                  label: Text(t(context, "I've found my path")),
                ),
                const SizedBox(height: 12),
                heading(
                  t(context, names[path]!),
                  t(context, 'Try a little. Discover a lot.'),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: t(context, '{stars} of 3 stars', {'stars': '$round'}),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              i < round
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              key: ValueKey('$i-${i < round}'),
                              color: i < round
                                  ? amber
                                  : Theme.of(context).colorScheme.outline,
                              size: 48,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (progress.rating != null)
                  ...result(context, progress)
                else if (!started && round == 0) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.sports_esports_outlined,
                            size: 48,
                            color: green,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t(context, 'Your mini adventure'),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t(
                              context,
                              'Play three short challenges, earn three stars, then make something small. Take about 5–10 minutes, or go at your own pace.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t(
                              context,
                              'Retries are unlimited. These stars do not count as completed lessons or learning points. Your full course opens only after you confirm you like this path.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => setState(() => started = true),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(t(context, 'Start my taster game')),
                  ),
                ] else if (round < 3) ...[
                  Text(
                    t(context, 'Challenge {current} of 3', {
                      'current': '${round + 1}',
                    }),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson['title'] as String,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            lesson['body'] as String,
                            style: const TextStyle(height: 1.6),
                          ),
                          if (lesson['code'] != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: SelectableText(
                                lesson['code'] as String,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  height: 1.5,
                                ),
                              ),
                            ),
                          const Divider(height: 30),
                          Text(
                            lesson['statement'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final value in [true, false])
                                FilledButton.tonal(
                                  key: ValueKey('taster-$round-$value'),
                                  onPressed: busy ? null : () => answer(value),
                                  child: Text(
                                    t(context, value ? 'True' : 'False'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  heading(
                    t(context, 'Three stars! Now make it yours.'),
                    t(
                      context,
                      'Try this small task from your matched course. Describe your attempt in at least 20 characters.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    lesson['practice'] as String,
                    style: const TextStyle(fontSize: 17, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: practice,
                    readOnly: busy,
                    minLines: 4,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: t(context, 'Your practice'),
                      hintText: t(
                        context,
                        'Write at least 20 characters. Your draft saves as you type.',
                      ),
                    ),
                    onChanged: (value) async {
                      setState(() => feedback = null);
                      try {
                        await store.saveTasterDraft(path, value);
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => feedback =
                                'Could not save your taster. Please try again.',
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  heading(
                    t(context, 'Does this feel like your path?'),
                    t(
                      context,
                      'Your honest reaction matters. You can explore again before committing.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy || practice.text.trim().runes.length < 20
                        ? null
                        : () => rate('love'),
                    icon: const Icon(Icons.favorite_outline),
                    label: Text(t(context, 'Yes, this is my path')),
                  ),
                  TextButton(
                    onPressed: busy || practice.text.trim().runes.length < 20
                        ? null
                        : () => rate('unsure'),
                    child: Text(t(context, 'I am not sure yet')),
                  ),
                  TextButton(
                    onPressed: busy || practice.text.trim().runes.length < 20
                        ? null
                        : () => rate('no'),
                    child: Text(t(context, 'This is not for me')),
                  ),
                ],
                if (feedback != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(t(context, feedback!)),
                    ),
                  ),
                if (busy)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  List<Widget> result(BuildContext context, TasterProgress progress) => [
    heading(
      t(
        context,
        progress.confirmed
            ? 'Your path is confirmed!'
            : progress.rating == 'no'
            ? 'It is okay to try another direction.'
            : 'Take your time. Keep exploring.',
      ),
      t(
        context,
        progress.confirmed
            ? 'You tried the taster and confirmed your interest. Your matched full course is now open.'
            : 'Your full course stays locked until you enjoy the taster and confirm your interest.',
      ),
    ),
    const SizedBox(height: 24),
    if (progress.confirmed)
      FilledButton.icon(
        onPressed: busy
            ? null
            : () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => CoursePage(store: store, path: store.path!),
                ),
              ),
        icon: const Icon(Icons.school_outlined),
        label: Text(t(context, 'Start my full course')),
      )
    else ...[
      FilledButton.icon(
        onPressed: busy
            ? null
            : () => run(() async {
                await store.replayTaster(store.path!);
                if (mounted) {
                  setState(() {
                    started = true;
                    practice.clear();
                  });
                }
              }),
        icon: const Icon(Icons.replay),
        label: Text(t(context, 'Play my taster again')),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => QuizPage(store: store)),
              ),
        child: Text(t(context, 'Find a different path')),
      ),
    ],
  ];
}
