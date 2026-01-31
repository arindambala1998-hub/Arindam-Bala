import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/token_store.dart';
import 'api_exception.dart';

/// Production-ready API client for Troonky.
/// - Adds Bearer token automatically
/// - Timeouts
/// - Safe error mapping
/// - Optional retry for idempotent requests
class ApiClient {
  final Dio _dio;

  ApiClient._(this._dio);

  static ApiClient? _instance;

  static ApiClient get instance {
    _instance ??= ApiClient._(_createDio());
    return _instance!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        // Keep baseUrl empty by default because some services already build absolute urls.
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 25),
        headers: const {
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStore.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (e, handler) {
          // Keep the original error for higher layers, but convert when needed.
          return handler.next(e);
        },
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          requestHeader: true,
          requestBody: false,
          responseHeader: false,
          responseBody: false,
        ),
      );
    }

    return dio;
  }

  // -------------------------
  // HTTP helpers
  // -------------------------
  Future<dynamic> get(
      String url, {
        Map<String, dynamic>? query,
        Options? options,
      }) async {
    return _wrap(() => _dio.get(url, queryParameters: query, options: options));
  }

  Future<dynamic> post(
      String url, {
        dynamic data,
        Map<String, dynamic>? query,
        Options? options,
      }) async {
    return _wrap(() => _dio.post(url, data: data, queryParameters: query, options: options));
  }

  Future<dynamic> put(
      String url, {
        dynamic data,
        Map<String, dynamic>? query,
        Options? options,
      }) async {
    return _wrap(() => _dio.put(url, data: data, queryParameters: query, options: options));
  }

  Future<dynamic> delete(
      String url, {
        dynamic data,
        Map<String, dynamic>? query,
        Options? options,
      }) async {
    return _wrap(() => _dio.delete(url, data: data, queryParameters: query, options: options));
  }

  Future<dynamic> _wrap(Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  ApiException _toApiException(DioException e) {
    final sc = e.response?.statusCode;
    final data = e.response?.data;

    String msg = 'Request failed';
    String? code;

    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      msg = (m['message'] ?? m['error'] ?? m['msg'] ?? msg).toString();
      code = (m['code'] ?? '').toString();
    } else if (data is String && data.trim().isNotEmpty) {
      msg = data.trim();
    } else {
      msg = e.message ?? msg;
    }

    // Friendly defaults
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      msg = 'Network timeout. Please try again.';
    }

    if (sc == 401) {
      msg = 'Session expired. Please login again.';
    }

    return ApiException(message: msg, statusCode: sc, code: code);
  }
}
