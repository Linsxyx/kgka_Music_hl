import 'dart:math';

/// Maintains a shuffled playback round without repeating an item.
///
/// The current item is treated as already played when a queue is first set.
/// Once the remaining items are exhausted, a new round containing every item
/// is shuffled. For queues with more than one item, a new round never starts
/// by immediately replaying the current item.
class ShuffleCycle<T> {
  ShuffleCycle({Random? random}) : _random = random ?? Random();

  final Random _random;
  List<T> _items = const [];
  List<T> _remaining = const [];

  void clear() {
    _items = const [];
    _remaining = const [];
  }

  void reset(Iterable<T> items, {T? current}) {
    _items = _unique(items);
    _remaining = List<T>.of(
      _items.where((item) => current == null || item != current),
    )..shuffle(_random);
  }

  void markPlayed(T item) {
    _remaining.removeWhere((candidate) => candidate == item);
  }

  T? next(Iterable<T> items, {T? current}) {
    final normalized = _unique(items);
    if (!_sameItems(_items, normalized)) {
      reset(normalized, current: current);
    }

    if (_remaining.isEmpty) {
      if (_items.isEmpty) return null;
      if (_items.length == 1) return _items.first;

      _remaining = List<T>.of(_items)..shuffle(_random);
      if (current != null && _remaining.last == current) {
        final replacementIndex = _remaining.indexWhere(
          (item) => item != current,
        );
        final replacement = _remaining[replacementIndex];
        _remaining[replacementIndex] = _remaining.last;
        _remaining[_remaining.length - 1] = replacement;
      }
    }

    return _remaining.removeLast();
  }

  List<T> _unique(Iterable<T> items) {
    final seen = <T>{};
    return [
      for (final item in items)
        if (seen.add(item)) item,
    ];
  }

  bool _sameItems(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
