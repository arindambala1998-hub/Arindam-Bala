import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiHelper {
  /// Keep /api included so other services can call: /products/1, /orders/create etc.
  static const String baseUrl = "https://adminapi.troonky.in/api";

  /// If your token key differs, change here only.
  static const String _tokenKey = "token";

  /// Network timeout
  static const Duration _timeout = Duration(seconds: 25);

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    if (t == null || t.trim().isEmpty) return null;
    return t.trim();
  }

  Uri _makeUri(String endpoint) {
    final ep = endpoint.trim();
    if (ep.startsWith("http://") || ep.startsWith("https://")) {
      return Uri.parse(ep);
    }
    // Ensure single slash
    if (ep.startsWith("/")) return Uri.parse("$baseUrl$ep");
    return Uri.parse("$baseUrl/$ep");
  }

  Map<String, String> _mergeHeaders(
      Map<String, String>? headers, {
        String? token,
        bool json = true,
        bool auth = true,
      }) {
    final h = <String, String>{};

    if (json) {
      h["Content-Type"] = "application/json";
      h["Accept"] = "application/json";
    }

    if (auth && token != null && token.isNotEmpty) {
      h["Authorization"] = "Bearer $token";
    }

    if (headers != null) h.addAll(headers);
    return h;
  }

  dynamic _decodeBody(String body) {
    final b = body.trim();
    if (b.isEmpty) return null;
    try {
      return json.decode(b);
    } catch (_) {
      // Non-JSON response (HTML / text)
      return {"raw": body};
    }
  }

  Future<dynamic> _handleResponse(http.Response res) async {
    final data = _decodeBody(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }

    // Try to extract a useful message
    String msg = "Request failed (${res.statusCode})";
    if (data is Map && data["message"] != null) {
      msg = data["message"].toString();
    } else if (data is Map && data["error"] != null) {
      msg = data["error"].toString();
    } else if (data is Map && data["raw"] != null) {
      msg = data["raw"].toString();
    }

    throw HttpException(msg);
  }

  /// GET
  Future<dynamic> get(
      String endpoint, {
        Map<String, String>? headers,
        bool auth = true,
      }) async {
    final token = auth ? await _getToken() : null;

    final res = await http
        .get(
      _makeUri(endpoint),
      headers: _mergeHeaders(headers, token: token, json: true, auth: auth),
    )
        .timeout(_timeout);

    return _handleResponse(res);
  }

  /// POST JSON
  Future<dynamic> post(
      String endpoint,
      Map<String, dynamic> body, {
        Map<String, String>? headers,
        bool auth = true,
      }) async {
    final token = auth ? await _getToken() : null;

    final res = await http
        .post(
      _makeUri(endpoint),
      headers: _mergeHeaders(headers, token: token, json: true, auth: auth),
      body: json.encode(body),
    )
        .timeout(_timeout);

    return _handleResponse(res);
  }

  /// PUT JSON
  Future<dynamic> put(
      String endpoint,
      Map<String, dynamic> body, {
        Map<String, String>? headers,
        bool auth = true,
      }) async {
    final token = auth ? await _getToken() : null;

    final res = await http
        .put(
      _makeUri(endpoint),
      headers: _mergeHeaders(headers, token: token, json: true, auth: auth),
      body: json.encode(body),
    )
        .timeout(_timeout);

    return _handleResponse(res);
  }

  /// DELETE
  Future<dynamic> delete(
      String endpoint, {
        Map<String, String>? headers,
        bool auth = true,
      }) async {
    final token = auth ? await _getToken() : null;

    final res = await http
        .delete(
      _makeUri(endpoint),
      headers: _mergeHeaders(headers, token: token, json: true, auth: auth),
    )
        .timeout(_timeout);

    return _handleResponse(res);
  }

  /// Multipart (images/files)
  /// files = List<File>, fieldName default "image"
  Future<dynamic> postMultipart(
      String endpoint,
      Map<String, String> fields,
      List<File> files, {
        Map<String, String>? headers,
        String fileField = "image",
        bool auth = true,
      }) async {
    final token = auth ? await _getToken() : null;

    final req = http.MultipartRequest("POST", _makeUri(endpoint));

    // Headers (do NOT set Content-Type for multipart manually)
    final h = <String, String>{
      "Accept": "application/json",
      if (auth && token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };
    if (headers != null) h.addAll(headers);
    req.headers.addAll(h);

    req.fields.addAll(fields);

    for (final f in files) {
      if (await f.exists()) {
        req.files.add(await http.MultipartFile.fromPath(fileField, f.path));
      }
    }

    final streamed = await req.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }
}
