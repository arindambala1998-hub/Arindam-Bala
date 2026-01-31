import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:http/http.dart' as http;

class SearchAPI {
  // আপনার API এর বেস URL
  static const String baseUrl = "https://adminapi.troonky.in/api";

  // প্রমাণীকরণের জন্য একটি placeholder Header, যদি প্রয়োজন হয়।
  // প্রয়োজনে এখানে আপনার JWT টোকেন যোগ করুন।
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    // 'Authorization': 'Bearer YOUR_AUTH_TOKEN_HERE', // <-- JWT যোগ করতে হলে
  };

  // -------------------------------------------------------------------------
  // 🔍 ইউজার সার্চ (নাম / ফোন / ইমেল)
  // -------------------------------------------------------------------------
  static Future<List<dynamic>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse("$baseUrl/profile/$query");

    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        // যদি সিঙ্গেল ইউজার প্রোফাইল ডেটা সরাসরি ম্যাপ (Map) আকারে আসে, তবে সেটিকে লিস্টে (List) মুড়ে রিটার্ন করা
        if (data is Map && data.containsKey("id")) {
          return [data];
        }

        // যদি API সরাসরি একটি লিস্ট রিটার্ন করে
        if (data is List) {
          return data;
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error searching users: $e");
    }

    return [];
  }

  // -------------------------------------------------------------------------
  // 🏬 শপ সার্চ (পিনকোড এর মাধ্যমে)
  // -------------------------------------------------------------------------
  static Future<List<dynamic>> searchShops(String pincode) async {
    if (pincode.isEmpty) return [];

    final url = Uri.parse("$baseUrl/shops?pincode=$pincode");

    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        // ধরে নেওয়া হলো API response বডিতে একটি Map দেয়, যেখানে 'shops' key-তে লিস্ট থাকে
        if (data is Map && data.containsKey("shops")) {
          return data["shops"];
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error searching shops: $e");
    }

    return [];
  }

  // -------------------------------------------------------------------------
  // 🛍️ প্রোডাক্ট সার্চ (শপ ID এর মাধ্যমে)
  // -------------------------------------------------------------------------
  static Future<List<dynamic>> searchProductsByShop(int shopId) async {
    final url = Uri.parse("$baseUrl/shops/$shopId/products");

    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        // ধরে নেওয়া হলো API response বডিতে একটি Map দেয়, যেখানে 'products' key-তে লিস্ট থাকে
        if (data is Map && data.containsKey("products")) {
          return data["products"];
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error searching products: $e");
    }

    return [];
  }

  // -------------------------------------------------------------------------
  // 📝 পোস্ট সার্চ (Fallback Search)
  // -------------------------------------------------------------------------
  static Future<List<dynamic>> searchPosts(String query) async {
    final url = Uri.parse("$baseUrl/posts/feed");

    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        // ✅ supports {items:[...]} OR {data:{items:[...]}}
        if (data is Map) {
          final root = Map<String, dynamic>.from(data);
          final d = (root["data"] is Map) ? Map<String, dynamic>.from(root["data"]) : <String, dynamic>{};
          final items = (root["items"] is List)
              ? (root["items"] as List)
              : (d["items"] is List)
              ? (d["items"] as List)
              : <dynamic>[];

          return items
              .where((post) =>
          post["description"] != null &&
              post["description"]
                  .toString()
                  .toLowerCase()
                  .contains(query.toLowerCase()))
              .toList();
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error searching posts: $e");
    }

    return [];
  }
}