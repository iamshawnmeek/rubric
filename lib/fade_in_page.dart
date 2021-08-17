import 'package:flutter/material.dart';

class FadeInPage<T> extends Page<T> {
  final Widget child;

  FadeInPage({
    required this.child,
  }) : super(key: ValueKey(child));

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder(
      settings: this,
      pageBuilder: (context, animation, animation2) {
        final tween = Tween(begin: 0.0, end: 1.0);
        final curveTween = CurveTween(curve: Curves.easeInOut);
        return FadeTransition(
          opacity: animation.drive(curveTween).drive(tween),
          child: child,
        );
      },
    );
  }
}
