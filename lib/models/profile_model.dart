class ProfileModel {
  final String id;
  final String type; // "normal", "business", "service"
  final String name;
  final String bio;
  final String profilePic;
  final String coverPic;
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> services;

  ProfileModel({
    required this.id,
    required this.type,
    required this.name,
    required this.bio,
    required this.profilePic,
    required this.coverPic,
    this.posts = const [],
    this.products = const [],
    this.services = const [],
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id']?.toString() ?? "0",
      type: json['user_type'] ?? json['type'] ?? 'normal',
      name: json['name'] ?? '',
      bio: json['bio'] ?? '',
      profilePic: json['profile_pic'] ?? '',
      coverPic: json['cover_pic'] ?? '',
      posts: List<Map<String, dynamic>>.from(json['posts'] ?? []),
      products: List<Map<String, dynamic>>.from(json['products'] ?? []),
      services: List<Map<String, dynamic>>.from(json['services'] ?? []),
    );
  }
}
