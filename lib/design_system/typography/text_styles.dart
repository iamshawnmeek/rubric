import 'package:flutter/painting.dart';
import 'package:rubric/design_system/colors.dart';

/// Font families bundled in assets/custom_fonts.
abstract final class Fonts {
  static const black = 'Avenir-Black';
  static const heavy = 'Avenir-Heavy';
  static const light = 'Avenir-Light';
}

/// Every text style in the design system. The typography widgets
/// (HeadlineOne, CardTitle, …) are thin wrappers over these so screens can use
/// either form; values are unchanged from the original designs.
abstract final class RubricTextStyles {
  static const headlineOne = TextStyle(
    color: white,
    fontFamily: Fonts.black,
    fontSize: 36,
  );

  static const bodyHeadline = TextStyle(
    fontFamily: Fonts.black,
    fontSize: 36,
    height: 1.2,
    color: white,
  );

  static const bodyOne = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 28,
    height: 1.3,
    color: white,
  );

  static const bodyPlaceholder = TextStyle(
    color: primaryLighter,
    fontFamily: Fonts.heavy,
    fontSize: 24,
    height: 1.2,
  );

  static const bodyWeights = TextStyle(
    color: white,
    fontFamily: Fonts.heavy,
    fontSize: 48,
    height: 1.3,
  );

  static const cardHint = TextStyle(
    color: primaryLight,
    fontFamily: Fonts.black,
    fontSize: 18,
  );

  static const cardTitle = TextStyle(
    color: white,
    fontFamily: Fonts.black,
    fontSize: 24,
  );

  static const cardNext = TextStyle(
    color: secondary,
    fontFamily: Fonts.black,
    fontSize: 20,
  );

  static const toggleActive = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 21,
    height: 1.2,
  );

  static const toggleInactive = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 21,
    height: 1.2,
    color: inactive,
  );

  static const gradingScaleInput = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 21,
    height: 1.2,
    color: primaryLighter,
  );

  /// Onboarding page body copy.
  static const pageInfo = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 24,
    height: 1.5,
    color: primaryLighter,
  );

  /// Label on accent buttons smaller than the full CTA.
  static const button = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 18,
    height: 1.3,
    color: secondary,
  );

  // Derived sizes for dense surfaces (lists, tables, chips). Same families and
  // colors as the card styles above, stepped down for information density.

  static const bodySmall = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 16,
    height: 1.35,
    color: primaryLighter,
  );

  static const caption = TextStyle(
    fontFamily: Fonts.heavy,
    fontSize: 14,
    height: 1.3,
    color: primaryLight,
  );

  static const sectionLabel = TextStyle(
    fontFamily: Fonts.black,
    fontSize: 14,
    letterSpacing: 1.2,
    color: primaryLight,
  );

  static const listTitle = TextStyle(
    fontFamily: Fonts.black,
    fontSize: 20,
    color: white,
  );

  static const statValue = TextStyle(
    fontFamily: Fonts.black,
    fontSize: 32,
    height: 1.1,
    color: white,
  );
}
