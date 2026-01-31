class ServiceOrderModel {
  final String serviceId;
  final String serviceName;
  final String customerName;
  final String mobile;
  final String address;
  final String date;
  final String time;
  final double price;
  final String paymentMethod;

  ServiceOrderModel({
    required this.serviceId,
    required this.serviceName,
    required this.customerName,
    required this.mobile,
    required this.address,
    required this.date,
    required this.time,
    required this.price,
    required this.paymentMethod,
  });

  Map<String, dynamic> toJson() => {
    "service_id": serviceId,
    "service_name": serviceName,
    "customer_name": customerName,
    "mobile": mobile,
    "address": address,
    "date": date,
    "time": time,
    "price": price,
    "payment_method": paymentMethod,
  };
}
