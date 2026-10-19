part of 'main.dart';

const courseDescriptions = {
  'data': 'Explore patterns and turn numbers into insights.',
  'web': 'Build websites and interactive experiences.',
  'cyber': 'Protect accounts, systems and information.',
  'ai': 'Explore intelligent tools and model predictions.',
  'design': 'Create clear and useful digital experiences.',
  'marketing': 'Connect an audience with a useful offer.',
  'business': 'Turn a customer problem into a business idea.',
  'writing': 'Make ideas clear through words.',
  'project': 'Organise people, tasks and outcomes.',
  'teaching': 'Help others understand and practise new skills.',
};

String libraryStatus(LearningStore store, String path) =>
    store.canAccessCourse(path)
    ? 'Available to learn'
    : store.path == path
    ? 'Taster confirmation needed'
    : 'Quiz match needed';

class LearningLibraryPage extends StatefulWidget {
  const LearningLibraryPage({super.key, required this.store});
  final LearningStore store;
  @override
  State<LearningLibraryPage> createState() => _LearningLibraryPageState();
}

class _LearningLibraryPageState extends State<LearningLibraryPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final courses = names.keys
          .where(
            (p) =>
                '${t(context, names[p]!)} ${t(context, courseDescriptions[p]!)}'
                    .toLowerCase()
                    .contains(query.trim().toLowerCase()),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            t(context, 'Learning Library'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                heading(
                  t(context, 'Explore every course'),
                  t(
                    context,
                    'Browse all ten courses. Full learning opens for your matched path after taster confirmation.',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t(context, '{courses} courses · {lessons} lessons', {
                    'courses': '${names.length}',
                    'lessons':
                        '${names.keys.fold<int>(0, (sum, path) => sum + store.ids(path).length)}',
                  }),
                ),
                const SizedBox(height: 20),
                TextField(
                  decoration: InputDecoration(
                    labelText: t(context, 'Search learning paths'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 20),
                if (courses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      t(context, 'No paths found. Try another search.'),
                    ),
                  ),
                ...courses.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      key: ValueKey('library-$path'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                LibraryCoursePage(store: store, path: path),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: amber.withValues(
                                      alpha: .2,
                                    ),
                                    child: Icon(
                                      icons[path],
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      t(context, names[path]!),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                t(context, courseDescriptions[path]!),
                                style: const TextStyle(height: 1.5),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    t(context, '{count} lessons · Beginner', {
                                      'count': '${store.ids(path).length}',
                                    }),
                                  ),
                                  Chip(
                                    avatar: Icon(
                                      store.canAccessCourse(path)
                                          ? Icons.lock_open
                                          : store.path == path
                                          ? Icons.sports_esports_outlined
                                          : Icons.lock_outline,
                                      size: 18,
                                    ),
                                    label: Text(
                                      t(context, libraryStatus(store, path)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t(context, 'View course outline'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class LibraryCoursePage extends StatelessWidget {
  const LibraryCoursePage({super.key, required this.store, required this.path});
  final LearningStore store;
  final String path;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (!names.containsKey(path)) return CourseGate(store: store);
      final matched = store.path == path;
      return Scaffold(
        appBar: AppBar(title: Text(t(context, 'Learning Library'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  icons[path],
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                heading(
                  t(context, names[path]!),
                  t(context, courseDescriptions[path]!),
                ),
                const SizedBox(height: 16),
                Text(
                  t(context, '{count} lessons · Beginner', {
                    'count': '${store.ids(path).length}',
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  t(context, libraryStatus(store, path)),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    context,
                    'You can preview every course outline here. Your quiz match and taster confirmation determine which full course you can study.',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => matched
                          ? learningDestination(store)
                          : QuizPage(store: store),
                    ),
                  ),
                  icon: Icon(
                    matched ? Icons.play_arrow_rounded : Icons.explore_outlined,
                  ),
                  label: Text(
                    t(
                      context,
                      matched
                          ? store.learningAction
                          : store.path == null
                          ? 'Find my path'
                          : 'Retake quiz',
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  t(context, 'Course outline'),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...store
                    .ids(path)
                    .indexed
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              child: Text('${entry.$1 + 1}'),
                            ),
                            title: Text(
                              (store.lessons[entry.$2]
                                      as Map<String, dynamic>)['title']
                                  as String,
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
