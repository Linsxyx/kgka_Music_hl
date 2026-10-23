import 'dart:math';

/// Maintains a shuffled playback round without repeating an item, while
/// recording playback history so `previous()` and `next()` can navigate
/// backward and forward through the actual shuffled order.
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
  final List<T> _history = <T>[];
  int _historyIndex = -1;

  void clear() {
    _items = const [];
    _remaining = const [];
    _history.clear();
    _historyIndex = -1;
  }

  void reset(Iterable<T> items, {T? current}) {
    _items = _unique(items);
    _remaining = List<T>.of(
      _items.where((item) => current == null || item != current),
    )..shuffle(_random);
    _history.clear();
    if (current != null && _items.contains(current)) {
      _history.add(current);
      _historyIndex = 0;
    } else {
      _historyIndex = -1;
    }
  }

  void markPlayed(T item) {
    _remaining.removeWhere((candidate) => candidate == item);
    if (_historyIndex >= 0 &&
        _historyIndex < _history.length &&
        _history[_historyIndex] == item) {
      return;
    }
    if (_historyIndex >= 0 && _historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(item);
    _historyIndex = _history.length - 1;
  }

  T? next(Iterable<T> items, {T? current}) {
    final normalized = _unique(items);
    if (!_sameItems(_items, normalized)) {
      reset(normalized, current: current);
    } else if (current != null &&
        (_historyIndex < 0 ||
            _historyIndex >= _history.length ||
            _history[_historyIndex] != current)) {
      markPlayed(current);
    }

    if (_historyIndex >= 0 && _historyIndex < _history.length - 1) {
      _historyIndex++;
      return _history[_historyIndex];
    }

    final drawn = _drawFromRemaining(current: current);
    if (drawn == null) {
      return null;
    }
    _history.add(drawn);
    _historyIndex = _history.length - 1;
    return drawn;
  }

  T? previous(Iterable<T> items, {T? current}) {
    final normalized = _unique(items);
    if (!_sameItems(_items, normalized)) {
      reset(normalized, current: current);
    } else if (current != null &&
        (_historyIndex < 0 ||
            _historyIndex >= _history.length ||
            _history[_historyIndex] != current)) {
      markPlayed(current);
    }

    if (_historyIndex > 0) {
      _historyIndex--;
      return _history[_historyIndex];
    }

    final drawn = _drawFromRemaining(current: current);
    if (drawn == null) {
      return null;
    }
    _history.insert(0, drawn);
    _historyIndex = 0;
    return drawn;
  }

  T? _drawFromRemaining({T? current}) {
    if (_remaining.isEmpty) {
      if (_items.isEmpty) return null;
      if (_items.length == 1) return _items.first;

      _remaining = List<T>.of(_items)..shuffle(_random);
      if (current != null && _remaining.last == current) {
        final replacementIndex = _remaining.indexWhere(
          (item) => item != current,
        );
        if (replacementIndex >= 0) {
          final replacement = _remaining[replacementIndex];
          _remaining[replacementIndex] = _remaining.last;
          _remaining[_remaining.length - 1] = replacement;
        }
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
