enum GroupSplitMode { exact, percentage }

abstract final class GroupSplitCalculator {
  static Map<String, int>? calculate({
    required int totalMinor,
    required Iterable<String> memberIds,
    required Map<String, double> values,
    required GroupSplitMode mode,
  }) {
    final ids = memberIds.toList(growable: false);
    if (totalMinor <= 0 || ids.isEmpty || values.length != ids.length) {
      return null;
    }
    if (values.keys.any((id) => !ids.contains(id)) ||
        values.values.any(
          (value) => value.isNaN || value.isInfinite || value < 0,
        )) {
      return null;
    }
    if (mode == GroupSplitMode.exact) {
      final result = values.map((id, value) => MapEntry(id, value.round()));
      return _sum(result) == totalMinor ? result : null;
    }
    if ((values.values.fold<double>(0, (sum, value) => sum + value) - 100)
            .abs() >
        0.01) {
      return null;
    }
    final result = <String, int>{};
    var assigned = 0;
    for (final entry in values.entries) {
      final amount = (totalMinor * entry.value / 100).floor();
      result[entry.key] = amount;
      assigned += amount;
    }
    var remainder = totalMinor - assigned;
    for (final id in result.keys) {
      if (remainder == 0) break;
      result[id] = result[id]! + 1;
      remainder--;
    }
    return result;
  }

  static int _sum(Map<String, int> values) =>
      values.values.fold<int>(0, (sum, value) => sum + value);
}
