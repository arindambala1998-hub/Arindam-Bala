class ProductModel {
  final String id;
  final String name;
  final String image;
  final List<String> images;
  final double price;
  final double? oldPrice;
  final String description;

  ProductModel({
    required this.id,
    required this.name,
    required this.image,
    required this.images,
    required this.price,
    this.oldPrice,
    required this.description,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json["_id"] ?? json["id"].toString(),
      name: json["name"] ?? "",
      image: json["image"] ?? "",
      images: json["images"] != null
          ? List<String>.from(json["images"])
          : [json["image"]],
      price: (json["price"] as num?)?.toDouble() ?? 0,
      oldPrice: (json["old_price"] as num?)?.toDouble(),
      description: json["description"] ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "image": image,
    "images": images,
    "price": price,
    "old_price": oldPrice,
    "description": description,
  };
}
