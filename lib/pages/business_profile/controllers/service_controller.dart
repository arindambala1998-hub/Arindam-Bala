import 'package:flutter/foundation.dart';
import 'dart:io';
// ServicesAPI ক্লাস এখন পাওয়া যাচ্ছে এবং এটি স্ট্যাটিক মেথড ব্যবহার করে।
import '../../../services/services_api.dart';

class ServiceController extends ChangeNotifier {
  // যেহেতু ServicesAPI এর সব মেথড স্ট্যাটিক, তাই ইনস্ট্যান্সের প্রয়োজন নেই।
  // ইনস্ট্যান্স থাকলে, ত্রুটি আসত: The static method 'addService' can't be accessed through an instance.
  // final ServicesAPI _servicesApi = ServicesAPI(); // <--- এই লাইনটি সম্পূর্ণ বাদ দেওয়া হলো।

  bool loading = false;
  List<dynamic> services = [];
  // shopId এর পরিবর্তে businessId ব্যবহার করা হতে পারে, তবে এখানে shopId রাখা হলো,
  // ধরে নেওয়া হলো এটিই API-তে businessId হিসেবে যাচ্ছে।
  String? shopId;

  ServiceController({this.shopId});

  /// LOAD ALL SERVICES
  // সমস্যা: The method 'getServices' isn't defined for the type 'ServicesAPI'.
  // সমাধান: মেথডটির নাম ServicesAPI.getBusinessServices (স্ট্যাটিক)।
  Future<void> loadServices(String businessId) async {
    // shopId প্যারামিটারটিকে API এর সাথে মেলাতে businessId হিসেবে ব্যবহার করা হলো।
    loading = true;
    notifyListeners();

    try {
      // ✅ ServicesAPI.getBusinessServices স্ট্যাটিক কল ব্যবহার করা হলো
      services = await ServicesAPI.getBusinessServices(businessId);
    } catch (e) {
      if (kDebugMode) print("Service load error: $e");
    }

    loading = false;
    notifyListeners();
  }

  /// ADD SERVICE
  // সমস্যা: 'Map<String, dynamic>' can't be assigned to 'bool' এবং 'The static method addService can't be accessed through an instance'
  // সমাধান: স্ট্যাটিক কল ব্যবহার করা হলো এবং 'success' key চেক করা হলো।
  Future<bool> addService({
    required Map<String, dynamic> body,
    required File? imageFile, // File? ঠিক আছে
  }) async {
    // ইমেজ ফাইল Null হলে API কল করা উচিত নয়
    if (imageFile == null) return false;

    try {
      // ✅ API কলটি সরাসরি CLASS NAME ব্যবহার করে করা হলো।
      final response = await ServicesAPI.addService(
          body: body,
          imageFile: imageFile
      );

      // ✅ Map রিটার্ন টাইপ থেকে 'success' key চেক করা হলো।
      bool success = response['success'] == true;

      // body-তে shopId/businessId থাকলে সার্ভিসগুলি রিলোড করা হলো
      if (success && body.containsKey("businessId")) {
        await loadServices(body["businessId"]);
      }
      return success;

    } catch (e) {
      if (kDebugMode) print("Add Service Error: $e");
      return false;
    }
  }

  /// DELETE SERVICE
  // সমস্যা: 'Map<String, dynamic>' can't be assigned to 'bool' এবং 'The static method deleteService can't be accessed through an instance'
  // সমাধান: স্ট্যাটিক কল ব্যবহার করা হলো এবং 'success' key চেক করা হলো।
  Future<bool> deleteService(String id, String businessId) async {
    try {
      // ✅ API কলটি সরাসরি CLASS NAME ব্যবহার করে করা হলো।
      final response = await ServicesAPI.deleteService(id);

      // ✅ Map রিটার্ন টাইপ থেকে 'success' key চেক করা হলো।
      bool success = response['success'] == true;

      if (success) {
        await loadServices(businessId);
      }
      return success;
    } catch (e) {
      if (kDebugMode) print("Delete Service Error: $e");
      return false;
    }
  }
}