/// Simple in-memory cache for this app session.
/// Keep it small and scoped to avoid leaks.
class MemoryCache {
  static final Map<String, Object> _map = <String, Object>{};

  static T? get<T>(String key) {
    final v = _map[key];
    if (v is T) return v;
    return null;
  }

  static void set<T extends Object>(String key, T value) {
    _map[key] = value;
  }

  static void remove(String key) {
    _map.remove(key);
  }

  static void clear() {
    _map.clear();
  }
}
