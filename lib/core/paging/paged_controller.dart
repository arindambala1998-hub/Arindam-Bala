import 'package:flutter/foundation.dart';

typedef PageLoader<T> = Future<List<T>> Function({required int page, required int limit});

/// Reusable pagination controller.
/// - Prevents duplicate loads
/// - Exposes loading/error/hasMore
class PagedController<T> extends ChangeNotifier {
  final int limit;
  final PageLoader<T> loader;

  final List<T> items = <T>[];

  bool loadingFirst = false;
  bool loadingNext = false;
  bool hasMore = true;
  String error = '';

  int _page = 0;

  PagedController({
    required this.loader,
    this.limit = 20,
  });

  Future<void> loadFirst() async {
    if (loadingFirst) return;
    loadingFirst = true;
    loadingNext = false;
    error = '';
    hasMore = true;
    _page = 0;
    items.clear();
    notifyListeners();

    try {
      final first = await loader(page: 1, limit: limit);
      items.addAll(first);
      _page = 1;
      hasMore = first.length >= limit;
    } catch (e) {
      error = e.toString();
      hasMore = false;
    } finally {
      loadingFirst = false;
      notifyListeners();
    }
  }

  Future<void> loadNext() async {
    if (!hasMore || loadingFirst || loadingNext) return;
    loadingNext = true;
    error = '';
    notifyListeners();

    try {
      final nextPage = _page + 1;
      final next = await loader(page: nextPage, limit: limit);
      if (next.isEmpty) {
        hasMore = false;
      } else {
        items.addAll(next);
        _page = nextPage;
        hasMore = next.length >= limit;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loadingNext = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();
}
