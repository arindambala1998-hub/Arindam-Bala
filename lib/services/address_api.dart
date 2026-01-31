import 'package:troonky_link/helpers/api_helper.dart';

/// ✅ Addresses API (production target)
/// Expected backend endpoints (recommended):
/// - GET    /addresses?user_id=...   (or /users/:id/addresses)
/// - POST   /addresses              body: { ... }
/// - PUT    /addresses/:id
/// - DELETE /addresses/:id
///
/// This service is defensive: it can read legacy shapes too.
class AddressAPI {
  static final ApiHelper _api = ApiHelper();

  static List<Map<String, dynamic>> _toList(dynamic v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      final inner = m['data'] ?? m['addresses'] ?? m['items'] ?? m['result'];
      return _toList(inner);
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<Map<String, dynamic>>> list({String? userId}) async {
    // If backend supports auth-based addresses, userId not required.
    final qp = (userId ?? '').trim();
    final ep = qp.isEmpty ? '/addresses' : '/addresses?user_id=$qp';
    final res = await _api.get(ep, auth: true);
    return _toList(res);
  }

  static Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final res = await _api.post('/addresses', payload, auth: true);
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'success': true, 'data': res};
  }

  static Future<Map<String, dynamic>> update(String id, Map<String, dynamic> payload) async {
    final rid = id.trim();
    final res = await _api.put('/addresses/$rid', payload, auth: true);
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'success': true, 'data': res};
  }

  static Future<void> remove(String id) async {
    final rid = id.trim();
    await _api.delete('/addresses/$rid', auth: true);
  }
}
