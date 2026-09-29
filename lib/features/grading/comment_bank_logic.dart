import 'package:collection/collection.dart';
import 'package:rubric/domain/evaluation.dart';

/// Pure list rules shared by the comment bank page and the grading picker.
abstract final class CommentBankLogic {
  /// Snippets whose text or category contains every word of [query]
  /// (case-insensitive), optionally limited to one [category] ('' means
  /// uncategorised, null means all). Order is preserved — the repository
  /// already returns most-used first.
  static List<CommentSnippet> filter(
    List<CommentSnippet> all,
    String query, {
    String? category,
  }) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return [
      for (final s in all)
        if ((category == null || s.category.trim() == category) &&
            words.every(
              (w) =>
                  s.text.toLowerCase().contains(w) ||
                  s.category.toLowerCase().contains(w),
            ))
          s,
    ];
  }

  /// Distinct non-empty categories, alphabetically.
  static List<String> categories(List<CommentSnippet> all) => all
      .map((s) => s.category.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .sorted((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Whether [text] is already in the bank, ignoring case and spacing.
  static bool contains(List<CommentSnippet> all, String text) {
    final key = _normalise(text);
    return key.isNotEmpty && all.any((s) => _normalise(s.text) == key);
  }

  static String _normalise(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
