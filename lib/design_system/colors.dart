import 'package:flutter/material.dart';

// The Rubric palette. These values come from the original design system and are
// the only colors the app uses — add a token here (with the designer) rather
// than inlining a Color anywhere else.

const primary = Color(0xff8F53D3); // purple
const primaryCard = Color(0xff8743D3); // purple lil lighter
const secondary = Color(0xff2F035F); // darker b/g purple
const primaryDark = Color(0xff6E27BC); // darker purple
const primaryLight = Color(0xffB78EE4); // lighter purple
const primaryLighter = Color(0xffD2BAED); // very light purple
const primaryLightest = Color(0xffB693DD); // very lightest purple
const accent = Color(0xffFFAD00); // accent orange
const lightGray = Color(0xff979797); // light gray for border
const inactive = Color(0xff9071B4); // lighter color for inactive state
const Color white = Colors.white;

/// An ordered ramp for data series (charts, distribution bars), drawn only from
/// the palette above so visualisations stay on-brand.
const seriesRamp = <Color>[
  accent,
  primaryLighter,
  primaryLight,
  primary,
  inactive,
  primaryDark,
];
