import 'package:flutter/material.dart';

class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  SmoothPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Pages enter from the trailing edge: right in LTR, left in RTL.
          final dir = Directionality.of(context) == TextDirection.rtl
              ? -1.0
              : 1.0;

          // Slide in from the trailing edge to center
          final slideIn =
              Tween<Offset>(begin: Offset(dir, 0.0), end: Offset.zero).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.fastEaseInToSlowEaseOut,
                  reverseCurve: Curves.fastOutSlowIn,
                ),
              );

          // Parallax slide out towards the leading edge
          final slideOut =
              Tween<Offset>(
                begin: Offset.zero,
                end: Offset(-0.25 * dir, 0.0),
              ).animate(
                CurvedAnimation(
                  parent: secondaryAnimation,
                  curve: Curves.fastEaseInToSlowEaseOut,
                  reverseCurve: Curves.fastOutSlowIn,
                ),
              );

          // Fade out outgoing page slightly to enhance depth
          final fadeOut = Tween<double>(begin: 1.0, end: 0.8).animate(
            CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut),
          );

          return SlideTransition(
            position: slideOut,
            child: FadeTransition(
              opacity: fadeOut,
              child: SlideTransition(position: slideIn, child: child),
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 320),
      );
}
