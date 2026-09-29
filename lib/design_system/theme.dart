import 'package:flutter/material.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/text_styles.dart';

/// Material theme derived from the Rubric tokens, so stock widgets (dialogs,
/// snackbars, switches, pickers) pick up the brand without per-call styling.
ThemeData buildRubricTheme() {
  const scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: secondary,
    secondary: primaryLight,
    onSecondary: secondary,
    surface: secondary,
    surfaceContainerHighest: primaryDark,
    surfaceContainerHigh: primaryDark,
    surfaceContainer: primaryCard,
    surfaceContainerLow: primary,
    onSurfaceVariant: primaryLighter,
    outline: lightGray,
    outlineVariant: inactive,
    error: accent,
    onError: secondary,
  );

  final shape = RoundedRectangleBorder(borderRadius: Corners.card);
  const bodyFamily = Fonts.heavy;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: secondary,
    canvasColor: secondary,
    fontFamily: bodyFamily,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      displayLarge: RubricTextStyles.bodyWeights,
      headlineLarge: RubricTextStyles.headlineOne,
      headlineMedium: RubricTextStyles.bodyOne,
      titleLarge: RubricTextStyles.cardTitle,
      titleMedium: RubricTextStyles.listTitle,
      bodyLarge: RubricTextStyles.bodySmall,
      bodyMedium: RubricTextStyles.bodySmall,
      labelLarge: RubricTextStyles.button,
      labelMedium: RubricTextStyles.caption,
      bodySmall: RubricTextStyles.caption,
    ).apply(bodyColor: white, displayColor: white),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: primaryDark,
      shape: shape,
      titleTextStyle: RubricTextStyles.cardTitle,
      contentTextStyle: RubricTextStyles.bodySmall,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: primaryLighter,
      contentTextStyle: RubricTextStyles.button,
      actionTextColor: primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: secondary,
        textStyle: RubricTextStyles.button,
        shape: shape,
        minimumSize: const Size(64, Sizes.minTap),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryLighter,
        textStyle: RubricTextStyles.button,
        minimumSize: const Size(48, Sizes.minTap),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryLighter,
        side: const BorderSide(color: primaryLight),
        textStyle: RubricTextStyles.button,
        shape: shape,
        minimumSize: const Size(64, Sizes.minTap),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: primaryDark,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: primaryDark,
      indicatorColor: accent,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => RubricTextStyles.caption.copyWith(
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? white : primaryLighter,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? secondary
              : primaryLighter,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: primaryDark,
      indicatorColor: accent,
      selectedIconTheme: IconThemeData(color: secondary),
      unselectedIconTheme: IconThemeData(color: primaryLighter),
      selectedLabelTextStyle: TextStyle(color: white, fontFamily: Fonts.heavy),
      unselectedLabelTextStyle: TextStyle(
        color: primaryLighter,
        fontFamily: Fonts.heavy,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? secondary : primaryLighter,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : primaryDark,
      ),
      trackOutlineColor: WidgetStateProperty.all(primaryLight),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: primaryDark,
      thumbColor: accent,
      overlayColor: Color(0x33FFAD00),
      valueIndicatorColor: primaryLighter,
      valueIndicatorTextStyle: RubricTextStyles.button,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: primary,
      hintStyle: RubricTextStyles.bodySmall,
      labelStyle: RubricTextStyles.caption,
      border: OutlineInputBorder(
        borderRadius: Corners.card,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Corners.card,
        borderSide: const BorderSide(color: accent, width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: primaryLighter,
      textColor: white,
      titleTextStyle: RubricTextStyles.listTitle,
      subtitleTextStyle: RubricTextStyles.caption,
    ),
    dividerTheme: const DividerThemeData(color: primaryDark, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    popupMenuTheme: PopupMenuThemeData(
      color: primaryDark,
      shape: shape,
      textStyle: RubricTextStyles.bodySmall.copyWith(color: white),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: primaryDark,
      headerBackgroundColor: primary,
      shape: shape,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(secondary),
      side: const BorderSide(color: primaryLight, width: 2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: primaryLighter,
        borderRadius: Corners.card,
      ),
      textStyle: RubricTextStyles.caption.copyWith(color: secondary),
    ),
  );
}
