part of 'main.dart';

bool communityFlag(Map<String, dynamic> item, String key) =>
    item[key] == 1 || item[key] == true;

class CirclesPanel extends StatefulWidget {
  const CirclesPanel({super.key, required this.store});
  final LearningStore store;
  @override
  State<CirclesPanel> createState() => _CirclesPanelState();
}

class _CirclesPanelState extends State<CirclesPanel> {
  final handle = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final bio = TextEditingController();
  final accessKey = GlobalKey();
  final mentorKey = GlobalKey();
  bool register = true;
  int section = 0;
  CommunityStore get c => widget.store.community;
  void scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: .1,
        );
      }
    });
  }

  void openShortcut(bool posting) {
    if (widget.store.path == null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => QuizPage(store: widget.store)),
      );
    } else if (!c.signedIn || c.profile.isEmpty) {
      scrollTo(accessKey);
      if (c.signedIn) unawaited(c.refresh());
    } else if (posting) {
      setState(() => section = 2);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkPostEditor(store: widget.store),
        ),
      );
    } else {
      setState(() => section = 1);
      scrollTo(mentorKey);
    }
  }

  Widget shortcuts() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 550
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: width,
            child: FilledButton.icon(
              key: const ValueKey('circles-post-shortcut'),
              style: FilledButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: const Color(0xFF20352D),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 22,
                ),
              ),
              onPressed: c.busy ? null : () => openShortcut(true),
              icon: const Icon(Icons.edit_square, size: 28),
              label: Text(
                t(context, 'Share your work'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(
            width: width,
            child: FilledButton.icon(
              key: const ValueKey('circles-mentor-shortcut'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 22,
                ),
              ),
              onPressed: c.busy ? null : () => openShortcut(false),
              icon: const Icon(Icons.school_outlined, size: 28),
              label: Text(
                t(context, 'Find a mentor'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.refresh());
    });
  }

  @override
  void dispose() {
    handle.dispose();
    password.dispose();
    name.dispose();
    bio.dispose();
    super.dispose();
  }

  Future<void> act(
    String method,
    String route, [
    Map<String, dynamic> data = const {},
  ]) async {
    try {
      await c.act(method, route, data);
    } on CommunityException {
      /* The shared error banner shows the reason. */
    }
  }

  Widget title(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      t(context, value),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    ),
  );
  Widget empty(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(t(context, value)),
  );
  Widget card(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
  Widget button(String label, VoidCallback callback) => TextButton(
    onPressed: c.busy ? null : callback,
    child: Text(t(context, label)),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final me = c.profile;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            t(context, 'Circles'),
            t(context, 'Learn with people who share your interests.'),
          ),
          const SizedBox(height: 12),
          shortcuts(),
          const SizedBox(height: 16),
          Text(
            t(
              context,
              'Local shared preview. Accounts on this computer can connect; cross-device access needs a hosted service.',
            ),
          ),
          if (c.error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t(context, c.error!)),
              ),
            ),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  t(
                    context,
                    c.connected
                        ? 'Community service connected'
                        : 'Community service offline',
                  ),
                ),
              ),
              IconButton(
                tooltip: t(context, 'Refresh'),
                onPressed: c.busy ? null : c.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (widget.store.path == null)
            CourseGate(store: widget.store, embedded: true)
          else if (!c.signedIn)
            ...authentication(context)
          else if (me.isEmpty)
            button('Refresh', c.refresh)
          else ...[
            card([
              Text(
                me['name'] as String,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(t(context, names[me['path']] ?? 'My course')),
              if (me['path'] != widget.store.path) ...[
                Text(
                  t(
                    context,
                    'Your course match changed. Update your circle interest to find similar learners.',
                  ),
                ),
                button(
                  'Update my interest',
                  () => act('POST', '/profile', {
                    'path': widget.store.path,
                    'discoverable': communityFlag(me, 'discoverable'),
                  }),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'Discoverable to learners on my path')),
                value: communityFlag(me, 'discoverable'),
                onChanged: c.busy
                    ? null
                    : (value) => act('POST', '/profile', {
                        'path': me['path'],
                        'discoverable': value,
                      }),
              ),
              button('Sign out', c.logout),
            ]),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in [
                  'My circle',
                  'Mentors',
                  'Work feed',
                ].indexed)
                  ChoiceChip(
                    label: Text(t(context, entry.$2)),
                    selected: section == entry.$1,
                    onSelected: (_) => setState(() => section = entry.$1),
                  ),
              ],
            ),
            if (section == 0) ...circles(context),
            if (section == 1) ...mentors(context),
            if (section == 2) ...feed(context),
          ],
        ],
      );
    },
  );

  List<Widget> authentication(BuildContext context) => [
    KeyedSubtree(
      key: accessKey,
      child: title(
        register ? 'Create a Circles account' : 'Sign in to Circles',
      ),
    ),
    Text(
      t(
        context,
        'Your name and learning interest are visible to peers. Passwords are never shared.',
      ),
    ),
    const SizedBox(height: 16),
    if (register) ...[
      TextField(
        controller: name,
        maxLength: 40,
        decoration: InputDecoration(labelText: t(context, 'Display name')),
      ),
      const SizedBox(height: 12),
    ],
    TextField(
      controller: handle,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: t(context, 'Handle'),
        helperText: t(context, '3–30 letters, numbers, underscores or hyphens'),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: password,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: t(context, 'Password'),
        helperText: t(context, 'At least 10 characters'),
      ),
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: c.busy
          ? null
          : () async {
              await c.authenticate(
                register: register,
                handle: handle.text,
                password: password.text,
                name: name.text,
                path: widget.store.path!,
              );
              password.clear();
            },
      child: Text(t(context, register ? 'Create account' : 'Sign in')),
    ),
    button(
      register ? 'I already have an account' : 'Create a Circles account',
      () => setState(() => register = !register),
    ),
  ];

  List<Widget> circles(BuildContext context) {
    final incoming = c
        .list('invites')
        .where((i) => communityFlag(i, 'incoming'));
    final outgoing = c
        .list('invites')
        .where((i) => !communityFlag(i, 'incoming'));
    return [
      title('My circle'),
      Text(
        t(
          context,
          'Invite learners with the same interest. They choose whether to join. Circles hold up to 12 people.',
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: c
            .list('members')
            .map(
              (m) => Chip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(m['name'] as String),
              ),
            )
            .toList(),
      ),
      title('Circle invitations'),
      if (incoming.isEmpty) empty('No circle invitations yet.'),
      ...incoming.map(
        (i) => card([
          Text(
            i['sender_name'] as String,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(t(context, i['status'] as String)),
          if (i['status'] == 'pending')
            Wrap(
              children: [
                button(
                  'Accept',
                  () => act('POST', '/invites/${i['id']}/respond', {
                    'accept': true,
                  }),
                ),
                button(
                  'Decline',
                  () => act('POST', '/invites/${i['id']}/respond', {
                    'accept': false,
                  }),
                ),
              ],
            ),
        ]),
      ),
      title('Learners with similar interests'),
      if (c.list('learners').isEmpty)
        empty(
          'No discoverable learners on your path yet. Other learners appear when they create accounts and share the same interest.',
        ),
      ...c
          .list('learners')
          .map(
            (learner) => card([
              Text(
                learner['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(t(context, names[learner['path']] ?? 'My course')),
              if (communityFlag(learner, 'member'))
                Text(t(context, 'Already in your circle'))
              else if (communityFlag(learner, 'pending'))
                Text(t(context, 'Invitation pending'))
              else
                button(
                  'Invite to my circle',
                  () => act('POST', '/invites', {'learner': learner['id']}),
                ),
            ]),
          ),
      title('Sent invitations'),
      if (outgoing.isEmpty) empty('No invitations sent yet.'),
      ...outgoing.map(
        (i) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(i['recipient_name'] as String),
          subtitle: Text(t(context, i['status'] as String)),
        ),
      ),
    ];
  }

  Future<void> messageDialog({
    required String title,
    required String label,
    required String route,
    required Map<String, dynamic> data,
    required String field,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => CommunityMessageDialog(title: title, label: label),
    );
    if (result != null) await act('POST', route, {...data, field: result});
  }

  List<Widget> mentors(BuildContext context) => [
    KeyedSubtree(key: mentorKey, child: title('Find a mentor')),
    Text(
      t(
        context,
        'Volunteer mentors share your learning interest. Experience is self-described, not independently verified.',
      ),
    ),
    if (c.list('mentors').isEmpty)
      empty('No volunteer mentors for your path yet.'),
    ...c
        .list('mentors')
        .map(
          (mentor) => card([
            Text(
              mentor['name'] as String,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(mentor['mentor_bio'] as String),
            button(
              'Request mentoring',
              () => messageDialog(
                title: 'Request mentoring',
                label: 'What would you like help with? (20+ characters)',
                route: '/guidance',
                data: {'mentor': mentor['id']},
                field: 'message',
              ),
            ),
          ]),
        ),
    title('Offer to mentor learners'),
    Text(
      t(
        context,
        'Describe your experience and what you can help with. Publishing makes you available for requests on your path.',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: bio,
      minLines: 3,
      maxLines: 6,
      maxLength: 1000,
      decoration: InputDecoration(
        labelText: t(context, 'Mentor introduction (30+ characters)'),
        hintText: c.profile['mentor_bio'] as String?,
      ),
    ),
    Wrap(
      children: [
        button(
          'Publish mentor offer',
          () => act('POST', '/mentor-offer', {
            'bio': bio.text.trim().isEmpty
                ? c.profile['mentor_bio'] ?? ''
                : bio.text,
            'available': true,
          }),
        ),
        if (communityFlag(c.profile, 'mentor_available'))
          button(
            'Pause mentor offer',
            () => act('POST', '/mentor-offer', {
              'bio': c.profile['mentor_bio'],
              'available': false,
            }),
          ),
      ],
    ),
    if (communityFlag(c.profile, 'mentor_available'))
      Text(t(context, 'Your mentor offer is available.')),
    title('Mentoring requests'),
    if (c.list('guidance').isEmpty) empty('No mentoring requests yet.'),
    ...c
        .list('guidance')
        .map(
          (g) => card([
            Text(
              (communityFlag(g, 'mentor_side')
                      ? g['learner_name']
                      : g['mentor_name'])
                  as String,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(t(context, g['status'] as String)),
            const SizedBox(height: 8),
            Text(g['message'] as String),
            if ((g['reply'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(g['reply'] as String),
              ),
            if (communityFlag(g, 'mentor_side') && g['status'] == 'pending')
              Wrap(
                children: [
                  button(
                    'Accept',
                    () => messageDialog(
                      title: 'Accept mentoring request',
                      label: 'Reply (optional)',
                      route: '/guidance/${g['id']}/respond',
                      data: {'accept': true},
                      field: 'reply',
                    ),
                  ),
                  button(
                    'Decline',
                    () => act('POST', '/guidance/${g['id']}/respond', {
                      'accept': false,
                      'reply': '',
                    }),
                  ),
                ],
              ),
          ]),
        ),
  ];

  Future<void> deletePost(Map<String, dynamic> post) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(dialogContext, 'Delete this post?')),
        content: Text(
          t(
            dialogContext,
            'This removes the post from the feed and removes any posting points it earned.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t(dialogContext, 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t(dialogContext, 'Delete')),
          ),
        ],
      ),
    );
    if (approved == true) await act('DELETE', '/posts/${post['id']}');
  }

  List<Widget> feed(BuildContext context) => [
    title('Share your work'),
    Text(
      t(
        context,
        'Posts earn 10 points each, up to 30 per day. Edits earn no extra points. Deleted posts lose their points; reposts do not earn again.',
      ),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: c.busy
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WorkPostEditor(store: widget.store),
              ),
            ),
      icon: const Icon(Icons.add),
      label: Text(t(context, 'New work post')),
    ),
    title('Work feed'),
    if (c.list('posts').isEmpty)
      empty(
        'No work shared in your circles yet. Share a small step you are proud of.',
      ),
    ...c
        .list('posts')
        .map(
          (post) => card([
            Text(
              post['title'] as String,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('${post['author_name']} · ${post['circle_owner']}'),
            Text(
              DateTime.tryParse(
                    post['created'] as String,
                  )?.toLocal().toString().substring(0, 16) ??
                  '',
            ),
            if (post['updated'] != post['created']) Text(t(context, 'Edited')),
            const SizedBox(height: 16),
            SelectableText(post['body'] as String),
            if ((post['url'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(post['url'] as String),
              ),
            if (communityFlag(post, 'own')) ...[
              const SizedBox(height: 12),
              Text(
                t(context, '{points} posting points', {
                  'points': '${post['points']}',
                }),
              ),
              Wrap(
                children: [
                  button(
                    'Edit post',
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            WorkPostEditor(store: widget.store, post: post),
                      ),
                    ),
                  ),
                  button('Delete post', () => deletePost(post)),
                ],
              ),
            ],
          ]),
        ),
  ];
}

class WorkPostEditor extends StatefulWidget {
  const WorkPostEditor({super.key, required this.store, this.post});
  final LearningStore store;
  final Map<String, dynamic>? post;
  @override
  State<WorkPostEditor> createState() => _WorkPostEditorState();
}

class _WorkPostEditorState extends State<WorkPostEditor> {
  late final TextEditingController title;
  late final TextEditingController body;
  late final TextEditingController url;
  String? circle;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.post?['title'] as String? ?? '');
    body = TextEditingController(text: widget.post?['body'] as String? ?? '');
    url = TextEditingController(text: widget.post?['url'] as String? ?? '');
    circle =
        widget.post?['circle_id'] as String? ??
        widget.store.community.state['own_circle'] as String?;
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        t(context, widget.post == null ? 'New work post' : 'Edit post'),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              t(
                context,
                'Share a project, what you tried, and what you learned. Your post is visible to members of the selected circle.',
              ),
            ),
            const SizedBox(height: 20),
            if (widget.post == null) ...[
              DropdownButtonFormField<String>(
                initialValue: circle,
                decoration: InputDecoration(labelText: t(context, 'Circle')),
                items: widget.store.community
                    .list('circles')
                    .map(
                      (c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['owner_name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: saving ? null : (v) => circle = v,
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: title,
              maxLength: 100,
              readOnly: saving,
              decoration: InputDecoration(
                labelText: t(context, 'Post title (3–100 characters)'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: body,
              minLines: 5,
              maxLines: 14,
              maxLength: 4000,
              readOnly: saving,
              decoration: InputDecoration(
                labelText: t(
                  context,
                  'Your work and learning (40+ characters)',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: url,
              readOnly: saving,
              decoration: InputDecoration(
                labelText: t(context, 'Project link (optional, HTTPS)'),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(t(context, error!)),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (title.text.trim().length < 3 ||
                          body.text.trim().length < 40 ||
                          circle == null) {
                        setState(
                          () => error = 'Check the form fields and try again.',
                        );
                        return;
                      }
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await widget.store.community.act(
                          widget.post == null ? 'POST' : 'PATCH',
                          widget.post == null
                              ? '/posts'
                              : '/posts/${widget.post!['id']}',
                          {
                            'circle': circle,
                            'title': title.text,
                            'body': body.text,
                            'url': url.text,
                          },
                        );
                        if (context.mounted) Navigator.pop(context);
                      } on CommunityException catch (e) {
                        if (mounted) {
                          setState(() {
                            saving = false;
                            error = e.message;
                          });
                        }
                      }
                    },
              icon: const Icon(Icons.check),
              label: Text(
                t(
                  context,
                  saving
                      ? 'Saving…'
                      : widget.post == null
                      ? 'Share with my circle'
                      : 'Save changes',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CommunityMessageDialog extends StatefulWidget {
  const CommunityMessageDialog({
    super.key,
    required this.title,
    required this.label,
  });
  final String title;
  final String label;
  @override
  State<CommunityMessageDialog> createState() => _CommunityMessageDialogState();
}

class _CommunityMessageDialogState extends State<CommunityMessageDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t(context, widget.title)),
    content: TextField(
      controller: controller,
      minLines: 3,
      maxLines: 8,
      maxLength: 2000,
      decoration: InputDecoration(labelText: t(context, widget.label)),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t(context, 'Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(t(context, 'Send request')),
      ),
    ],
  );
}
