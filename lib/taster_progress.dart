import 'dart:convert';

class TasterProgress {
  const TasterProgress({this.stars = 0, this.draft = '', this.rating});
  final int stars;
  final String draft;
  final String? rating;
  bool get ready => stars == 3 && draft.trim().runes.length >= 20;
  bool get confirmed => ready && rating == 'love';

  static TasterProgress read(String? raw, String? assessment) {
    try {
      final data = jsonDecode(raw ?? 'null') as Map<String, dynamic>;
      if (assessment == null ||
          data['assessment'] != assessment ||
          data['version'] != 1) {
        return const TasterProgress();
      }
      final stars = data['stars'] as int;
      final draft = data['draft'] as String;
      final rating = data['rating'] as String?;
      if (stars < 0 ||
          stars > 3 ||
          (rating != null && !['love', 'unsure', 'no'].contains(rating))) {
        return const TasterProgress();
      }
      final progress = TasterProgress(
        stars: stars,
        draft: draft,
        rating: rating,
      );
      if (rating != null && !progress.ready) return const TasterProgress();
      return progress;
    } catch (_) {
      return const TasterProgress();
    }
  }

  String encode(String assessment) => jsonEncode({
    'version': 1,
    'assessment': assessment,
    'stars': stars,
    'draft': draft,
    'rating': rating,
  });
}
