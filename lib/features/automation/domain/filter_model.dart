class BotFilters {
  final String? storeCode;
  final double maxDistance;
  final double minPay;
  final List<String> orderTypes;

  BotFilters({
    this.storeCode,
    this.maxDistance = 5.0,
    this.minPay = 15.0,
    this.orderTypes = const ['Shopping', 'Pickup'],
  });

  Map<String, dynamic> toJson() => {
    'storeCode': storeCode,
    'maxDistance': maxDistance,
    'minPay': minPay,
    'orderTypes': orderTypes,
  };

  factory BotFilters.fromJson(Map<String, dynamic> json) => BotFilters(
    storeCode: json['storeCode'],
    maxDistance: (json['maxDistance'] as num).toDouble(),
    minPay: (json['minPay'] as num).toDouble(),
    orderTypes: List<String>.from(json['orderTypes'] ?? []),
  );

  BotFilters copyWith({
    String? storeCode,
    double? maxDistance,
    double? minPay,
    List<String>? orderTypes,
  }) {
    return BotFilters(
      storeCode: storeCode ?? this.storeCode,
      maxDistance: maxDistance ?? this.maxDistance,
      minPay: minPay ?? this.minPay,
      orderTypes: orderTypes ?? this.orderTypes,
    );
  }
}