class BotFilters {
  final String? storeCode;
  final double maxDistance;
  final double minPay;
  final List<String> orderTypes;

  BotFilters({
    this.storeCode,
    this.maxDistance = 5.0,
    double minPay = 20.0,
    this.orderTypes = const ['Compras', 'Recolección'],
  }) : minPay = minPay < 20.0 ? 20.0 : minPay;

  Map<String, dynamic> toJson() => {
    'storeCode': storeCode,
    'maxDistance': maxDistance,
    'minPay': minPay,
    'orderTypes': orderTypes,
  };

  factory BotFilters.fromJson(Map<String, dynamic> json) {
    return BotFilters(
      storeCode: json['storeCode'] as String?,
      maxDistance: (json['maxDistance'] as num?)?.toDouble() ?? 5.0,
      minPay: (json['minPay'] as num?)?.toDouble() ?? 20.0,
      orderTypes: json['orderTypes'] != null 
          ? List<String>.from(json['orderTypes']) 
          : const ['Compras', 'Recolección'],
    );
  }

  BotFilters copyWith({
    Object? storeCode = _sentinel,
    double? maxDistance,
    double? minPay,
    List<String>? orderTypes,
  }) {
    return BotFilters(
      storeCode: storeCode == _sentinel ? this.storeCode : (storeCode as String?),
      maxDistance: maxDistance ?? this.maxDistance,
      minPay: minPay ?? this.minPay,
      orderTypes: orderTypes ?? this.orderTypes,
    );
  }

  static const _sentinel = Object();
}
