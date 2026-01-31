// lib/models/signup_data.dart
// =======================================================
// SIGNUP DATA MODEL (FINAL • PRODUCTION READY • TROONKY)
// =======================================================

import 'dart:io';

class SignupData {
  // -------------------------------------------------------
  // USER TYPE
  // -------------------------------------------------------
  String userType = "user"; // "user" | "business"

  // -------------------------------------------------------
  // AUTH
  // -------------------------------------------------------
  String? emailOrPhone;
  String? password;

  // Optional but needed by backend (as you used in curl)
  String? phone;

  // -------------------------------------------------------
  // PERSONAL USER FIELDS
  // -------------------------------------------------------
  String? name;
  String? username; // optional (you used earlier)
  DateTime? dob;
  String? gender;

  String? address;
  String? pincode;
  String? country;
  String? state;

  String? bio;
  String? relationshipStatus;

  // Extra (future profile completeness)
  String? education;
  String? work;
  String? website;

  // -------------------------------------------------------
  // BUSINESS FIELDS
  // -------------------------------------------------------
  String? shopName;
  String? shopCategory;
  String? shopAddress;
  String? shopDescription;

  // -------------------------------------------------------
  // MEDIA
  // -------------------------------------------------------
  File? profilePicFile;
  File? coverPicFile;

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------
  bool get isBusiness => userType.toLowerCase() == "business";

  String? get displayName => isBusiness ? shopName : name;
  String? get displayAddress => isBusiness ? shopAddress : address;

  // -------------------------------------------------------
  // FINAL REGISTER PAYLOAD (API SAFE)
  // -------------------------------------------------------
  Map<String, dynamic> toRegisterPayload() {
    final type = userType.toLowerCase();

    // backend expects:
    // userType, email_or_phone, password, phone,
    // name, username (optional),
    // address, pincode, gender, date_of_birth/dob, relationship, bio, website, education, work
    // business fields: shop_name, shop_category, shop_address, description
    //
    // NOTE: we keep both "dob" and "date_of_birth" for compatibility (backend may use one)

    final payload = <String, dynamic>{
      "userType": type,
      "email_or_phone": emailOrPhone,
      "password": password,

      // optional fields
      if (phone != null && phone!.trim().isNotEmpty) "phone": phone!.trim(),
      if (username != null && username!.trim().isNotEmpty) "username": username!.trim(),

      // common
      "name": displayName,
      "address": displayAddress,
      "pincode": pincode,
      if (country != null) "country": country,
      if (state != null) "state": state,
    };

    if (!isBusiness) {
      payload.addAll({
        // personal
        if (dob != null) "dob": dob!.toIso8601String(),
        if (dob != null) "date_of_birth": dob!.toIso8601String(), // alias
        if (gender != null) "gender": gender,
        if (bio != null) "bio": bio,
        if (relationshipStatus != null) "relationship_status": relationshipStatus,
        if (relationshipStatus != null) "relationship": relationshipStatus, // alias

        // extra
        if (education != null) "education": education,
        if (work != null) "work": work,
        if (website != null) "website": website,
      });
    } else {
      payload.addAll({
        // business
        "shop_name": shopName,
        if (shopCategory != null) "shop_category": shopCategory,
        "shop_address": shopAddress,
        if (shopDescription != null) "description": shopDescription,

        // (optional) keep bio null for business unless backend uses it
        // "bio": null,
      });
    }

    return payload;
  }

  // -------------------------------------------------------
  // RESET
  // -------------------------------------------------------
  void clear() {
    userType = "user";

    emailOrPhone = null;
    password = null;
    phone = null;
    username = null;

    name = null;
    dob = null;
    gender = null;
    address = null;
    pincode = null;
    country = null;
    state = null;
    bio = null;
    relationshipStatus = null;

    education = null;
    work = null;
    website = null;

    shopName = null;
    shopCategory = null;
    shopAddress = null;
    shopDescription = null;

    profilePicFile = null;
    coverPicFile = null;
  }
}
