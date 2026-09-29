import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rubric/design_system/colors.dart' as palette;

/// The Avenir faces the app ships, loaded for embedding in PDFs.
class ExportFonts {
  const new({required this.light, required this.heavy, required this.black});

  static const _dir = 'assets/custom_fonts';

  /// Loads the fonts from [bundle] (the app's `rootBundle`).
  static Future<ExportFonts> load(AssetBundle bundle) async {
    Future<pw.Font> font(String name) async =>
        pw.Font.ttf(await bundle.load('$_dir/Avenir-$name.ttf'));
    return ExportFonts(
      light: await font('Light'),
      heavy: await font('Heavy'),
      black: await font('Black'),
    );
  }

  final pw.Font light;
  final pw.Font heavy;
  final pw.Font black;
}

/// Palette tokens as PDF colors. Documents use the app's purples and orange
/// for type, rules and header rows, and pale tints of them for fills, so they
/// read as Rubric on screen but spend little ink on white paper.
abstract final class PdfPalette {
  static PdfColor _c(Color c) => PdfColor.fromInt(c.toARGB32());

  /// Tints [c] towards white; [strength] is how much of [c] remains.
  static PdfColor _tint(Color c, double strength) {
    final base = _c(c);
    return PdfColor(base.red, base.green, base.blue, strength).flatten();
  }

  static final PdfColor ink = _c(palette.secondary);
  static final PdfColor heading = _c(palette.primaryDark);
  static final PdfColor primary = _c(palette.primary);
  static final PdfColor muted = _c(palette.lightGray);
  static final PdfColor accent = _c(palette.accent);
  static final PdfColor white = _c(palette.white);
  static final PdfColor rule = _tint(palette.primaryLight, .6);
  static final PdfColor band = _tint(palette.primaryLighter, .25);
  static final PdfColor highlight = _tint(palette.accent, .28);
}

/// Text styles for exported documents, sized for print (points, not dp).
class PdfStyles {
  new(this.fonts);

  final ExportFonts fonts;

  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: fonts.heavy,
    bold: fonts.black,
  ).copyWith(defaultTextStyle: body);

  pw.TextStyle get title =>
      pw.TextStyle(font: fonts.black, fontSize: 24, color: PdfPalette.ink);

  pw.TextStyle get subtitle =>
      pw.TextStyle(font: fonts.heavy, fontSize: 15, color: PdfPalette.heading);

  pw.TextStyle get meta =>
      pw.TextStyle(font: fonts.heavy, fontSize: 9.5, color: PdfPalette.muted);

  pw.TextStyle get section =>
      pw.TextStyle(font: fonts.black, fontSize: 14, color: PdfPalette.heading);

  pw.TextStyle get label => pw.TextStyle(
    font: fonts.black,
    fontSize: 8.5,
    letterSpacing: 1,
    color: PdfPalette.primary,
  );

  pw.TextStyle get body =>
      pw.TextStyle(font: fonts.heavy, fontSize: 10, color: PdfPalette.ink);

  pw.TextStyle get bodyStrong =>
      pw.TextStyle(font: fonts.black, fontSize: 10, color: PdfPalette.ink);

  pw.TextStyle get small =>
      pw.TextStyle(font: fonts.light, fontSize: 8.5, color: PdfPalette.ink);

  pw.TextStyle get tableHeader =>
      pw.TextStyle(font: fonts.black, fontSize: 9, color: PdfPalette.white);

  pw.TextStyle get grade =>
      pw.TextStyle(font: fonts.black, fontSize: 30, color: PdfPalette.ink);
}
