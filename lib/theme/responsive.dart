import 'package:flutter/material.dart';

/// Responsive design utilities following clean architecture patterns
class ResponsiveBreakpoints {
  static const double mobile = 480;
  static const double tablet = 768;
  static const double desktop = 1024;
  static const double wide = 1920;
}

/// Extension to easily check screen size
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  bool get isMobile => screenWidth < ResponsiveBreakpoints.tablet;
  bool get isTablet =>
      screenWidth >= ResponsiveBreakpoints.tablet &&
      screenWidth < ResponsiveBreakpoints.desktop;
  bool get isDesktop => screenWidth >= ResponsiveBreakpoints.desktop;

  EdgeInsets get responsivePadding {
    if (isMobile) return const EdgeInsets.all(12);
    if (isTablet) return const EdgeInsets.all(16);
    return const EdgeInsets.all(20);
  }

  double get responsiveSpacing {
    if (isMobile) return 8.0;
    if (isTablet) return 12.0;
    return 16.0;
  }
}

/// Responsive layout builder widget
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop) return desktop ?? tablet ?? mobile;
    if (context.isTablet) return tablet ?? mobile;
    return mobile;
  }
}
