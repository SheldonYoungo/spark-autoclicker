class BotFilters {
  final String? storeCode;
  final double maxDistance;
  final double minPay;
  final double maxPay;
  final List<String> orderTypes;
  final double speedMultiplier;
  final int scanSpeed;

  BotFilters({
    String? storeCode,
    double maxDistance = 10.0,
    double minPay = 13.0,
    double maxPay = 150.0,
    this.orderTypes = const ['Compras', 'Recolección'],
    this.speedMultiplier = 1.5,
    int? scanSpeed,
  })  : storeCode = storeCode,
        maxDistance = maxDistance > 100.0 ? 100.0 : (maxDistance < 1.0 ? 1.0 : maxDistance),
        minPay = minPay < 13.0 ? 13.0 : (minPay > 150.0 ? 150.0 : minPay),
        maxPay = maxPay > 150.0 ? 150.0 : (maxPay < minPay ? minPay : maxPay),
        scanSpeed = scanSpeed ?? _calculateDelay(speedMultiplier);

  static int _calculateDelay(double multiplier) {
    if (multiplier >= 3.0) return 100;
    if (multiplier >= 2.0) return 300;
    if (multiplier >= 1.5) return 500;
    return 1000;
  }

  Map<String, dynamic> toJson() => {
        'storeCode': storeCode,
        'maxDistance': maxDistance,
        'minPay': minPay,
        'maxPay': maxPay,
        'orderTypes': orderTypes,
        'speedMultiplier': speedMultiplier,
        'scanSpeed': scanSpeed,
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
      speedMultiplier: (json['speedMultiplier'] as num?)?.toDouble() ?? 1.5,
      scanSpeed: json['scanSpeed'] as int?,
    );
  }

  BotFilters copyWith({
    Object? storeCode = _sentinel,
    double? maxDistance,
    double? minPay,
    double? maxPay,
    List<String>? orderTypes,
    double? speedMultiplier,
    int? scanSpeed,
  }) {
    final newMultiplier = speedMultiplier ?? this.speedMultiplier;
    return BotFilters(
      storeCode:
          storeCode == _sentinel ? this.storeCode : (storeCode as String?),
      maxDistance: maxDistance ?? this.maxDistance,
      minPay: minPay ?? this.minPay,
      maxPay: maxPay ?? this.maxPay,
      orderTypes: orderTypes ?? this.orderTypes,
      speedMultiplier: newMultiplier,
      scanSpeed: scanSpeed ?? (speedMultiplier != null ? _calculateDelay(newMultiplier) : this.scanSpeed),
    );
  }

  static const Map<String, String> typeDisplayLabels = {
    'compras': 'Compras',
    'recolección': 'Recolección-Retiro',
    'multiviajes': 'Multiviajes',
  };

  String get orderTypesDisplay =>
      orderTypes.map((t) => BotFilters.typeDisplayLabels[t] ?? t).join(' · ');

  static const _sentinel = Object();
}
