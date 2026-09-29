import 'package:flutter/widgets.dart';
import 'package:rubric/design_system/components/rubric_card.dart'
    show RubricCard;
import 'package:rubric/design_system/design_system.dart' show RubricCard;

/// Spacing and shape tokens, extracted from the measurements the original
/// screens used (24pt page gutters, 10pt card radius, 36pt section breaks).
abstract final class Insets {
  static const double xs = 7;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 36;
  static const double xxl = 46;
  static const double pageTop = 36;

  /// Horizontal gutter every full-width page uses.
  static const page = EdgeInsets.symmetric(horizontal: lg);

  /// Internal padding of a [RubricCard]-style surface.
  static const card = EdgeInsets.symmetric(horizontal: 24, vertical: 18);
}

abstract final class Corners {
  static const double radius = 10;
  static final card = BorderRadius.circular(radius);
  static const dropTarget = Radius.circular(12);
}

abstract final class Sizes {
  /// Height of the accent call-to-action button (Next / Set Grading Scale).
  static const double ctaHeight = 75;

  /// Minimum tap target, per platform accessibility guidance.
  static const double minTap = 48;
}
