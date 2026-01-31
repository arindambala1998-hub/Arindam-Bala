class OrderModel {
  final String orderId;
  final String productName;
  final String productImage;
  final int quantity;
  final double totalPrice;
  final String address;
  final String paymentMethod;
  final DateTime date;

  OrderModel({
    required this.orderId,
    required this.productName,
    required this.productImage,
    required this.quantity,
    required this.totalPrice,
    required this.address,
    required this.paymentMethod,
    required this.date,
  });
}
