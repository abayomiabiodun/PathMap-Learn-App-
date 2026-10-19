import 'dart:convert';

const assessmentPaths = [
  'data',
  'web',
  'cyber',
  'ai',
  'design',
  'marketing',
  'business',
  'writing',
  'project',
  'teaching',
];

/// Matching measures enjoyment of actual course activities, never ability.
class PathAssessment {
  const PathAssessment({
    required this.ratings,
    required this.answers,
    required this.path,
  });
  final Map<String, int> ratings;
  final Map<String, bool> answers;
  final String path;

  static List<String> matches(Map<String, int> ratings) {
    if (ratings.length != assessmentPaths.length ||
        assessmentPaths.any(
          (p) => !ratings.containsKey(p) || ratings[p]! < 0 || ratings[p]! > 3,
        )) {
      return [];
    }
    final highest = ratings.values.reduce((a, b) => a > b ? a : b);
    return highest == 0
        ? []
        : assessmentPaths.where((p) => ratings[p] == highest).toList();
  }

  static PathAssessment? read(String? raw) {
    try {
      final data = jsonDecode(raw ?? 'null') as Map<String, dynamic>;
      if (data['version'] != 2) return null;
      final ratings = Map<String, int>.from(data['ratings'] as Map);
      final answers = Map<String, bool>.from(data['answers'] as Map);
      final path = data['path'] as String;
      if (answers.length != assessmentPaths.length ||
          assessmentPaths.any((p) => !answers.containsKey(p)) ||
          !matches(ratings).contains(path)) {
        return null;
      }
      return PathAssessment(ratings: ratings, answers: answers, path: path);
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'version': 2,
    'ratings': ratings,
    'answers': answers,
    'path': path,
  });
}

class AssessmentDraft {
  const AssessmentDraft({
    this.ratings = const {},
    this.answers = const {},
    this.step = 0,
  });
  final Map<String, int> ratings;
  final Map<String, bool> answers;
  final int step;
  static AssessmentDraft read(String? raw) {
    try {
      final data = jsonDecode(raw ?? 'null') as Map<String, dynamic>;
      if (data['version'] != 2) return const AssessmentDraft();
      final ratings = Map<String, int>.from(data['ratings'] as Map);
      final answers = Map<String, bool>.from(data['answers'] as Map);
      final step = data['step'] as int;
      if (step < 0 ||
          step > assessmentPaths.length ||
          ratings.keys.any((p) => !assessmentPaths.contains(p)) ||
          answers.keys.any((p) => !assessmentPaths.contains(p)) ||
          ratings.values.any((r) => r < 0 || r > 3) ||
          ratings.keys.any((p) => !answers.containsKey(p)) ||
          assessmentPaths.take(step).any((p) => !ratings.containsKey(p))) {
        return const AssessmentDraft();
      }
      return AssessmentDraft(ratings: ratings, answers: answers, step: step);
    } catch (_) {
      return const AssessmentDraft();
    }
  }

  String encode() => jsonEncode({
    'version': 2,
    'ratings': ratings,
    'answers': answers,
    'step': step,
  });
}
