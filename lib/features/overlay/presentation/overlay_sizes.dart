class OverlaySizes {
  final double screenWidth;
  final double screenHeight;

  OverlaySizes({required this.screenWidth, required this.screenHeight});

  static const double bubbleSize = 70;
  static const double collapsedWindowPadding = 5;
  static const double collapsedWindow = bubbleSize + collapsedWindowPadding * 2;

  bool get isSmallScreen => screenWidth < 360;
  bool get isLargeScreen => screenWidth >= 450;
  bool get isShortScreen => screenHeight < 700;

  int get panelWidth {
    final ratio = isSmallScreen ? 0.88 : 0.85;
    final minW = isSmallScreen ? 240.0 : 280.0;
    final maxW = isLargeScreen ? 420.0 : 380.0;
    return (screenWidth * ratio).clamp(minW, maxW).toInt();
  }

  int get panelHeight {
    final ratio = isShortScreen ? 0.85 : 0.80;
    return (screenHeight * ratio).clamp(320.0, 600.0).toInt();
  }

  double get fontScale => isSmallScreen ? 0.85 : 1.0;

  double get spacingScale => isSmallScreen ? 0.75 : 1.0;
}
