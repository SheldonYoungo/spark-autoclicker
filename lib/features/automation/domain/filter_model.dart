class BotFilters {
  final String? storeCode;
  final double maxDistance;
  final double minPay;
  final double maxPay;
  final List<String> orderTypes;

  BotFilters({
    String? storeCode,
    double maxDistance = 10.0,
    double minPay = 13.0,
    double maxPay = 150.0,
    this.orderTypes = const ['Compras', 'Recolección'],
  })  : storeCode = (storeCode != null && storeCode.length > 6) ? storeCode.substring(0, 6) : storeCode,
        maxDistance = maxDistance > 100.0 ? 100.0 : (maxDistance < 1.0 ? 1.0 : maxDistance),
        minPay = minPay < 13.0 ? 13.0 : (minPay > 150.0 ? 150.0 : minPay),
        maxPay = maxPay > 150.0 ? 150.0 : (maxPay < minPay ? minPay : maxPay);

  Map<String, dynamic> toJson() => {
        'storeCode': storeCode,
        'maxDistance': maxDistance,
        'minPay': minPay,
        'maxPay': maxPay,
        'orderTypes': orderTypes,
      };

  factory BotFilters.fromJson(Map<String, dynamic> json) {
    return BotFilters(
      storeCode: json['storeCode'] as String?,
      maxDistance: (json['maxDistance'] as num?)?.toDouble() ?? 10.0,
      minPay: (json['minPay'] as num?)?.toDouble() ?? 13.0,
      maxPay: (json['maxPay'] as num?)?.toDouble() ?? 150.0,
      orderTypes: json['orderTypes'] != null
          ? List<String>.from(json['orderTypes'])
          : const ['Compras', 'Recolección'],
    );
  }

  BotFilters copyWith({
    Object? storeCode = _sentinel,
    double? maxDistance,
    double? minPay,
    double? maxPay,
    List<String>? orderTypes,
  }) {
    return BotFilters(
      storeCode:
          storeCode == _sentinel ? this.storeCode : (storeCode as String?),
      maxDistance: maxDistance ?? this.maxDistance,
      minPay: minPay ?? this.minPay,
      maxPay: maxPay ?? this.maxPay,
      orderTypes: orderTypes ?? this.orderTypes,
    );
  }

  static const _sentinel = Object();
}
