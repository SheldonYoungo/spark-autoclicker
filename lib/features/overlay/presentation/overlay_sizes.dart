class OverlaySizes {
  final double screenWidth;
  final double screenHeight;

  OverlaySizes({
    required this.screenWidth,
    required this.screenHeight,
  });

  bool get isSmallScreen => screenWidth < 360;
  bool get isShortScreen => screenHeight < 700;

  static int get collapsedWindow => 80;
  static double get bubbleSize => 70;

  int get panelWidth {
    return (screenWidth * 0.80).clamp(260.0, 360.0).toInt();
  }

  int get panelHeight {
    final ratio = isShortScreen ? 0.80 : 0.75;
    return (screenHeight * ratio).clamp(300.0, 560.0).toInt();
  }

  double get fontScale => isSmallScreen ? 0.85 : 1.0;

  double get spacingScale => isSmallScreen ? 0.75 : 1.0;
}
