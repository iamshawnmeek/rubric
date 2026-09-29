import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale, Rect;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rubric/features/export/export_platform.dart';
import 'package:rubric/features/export/pdf_style.dart';
import 'package:rubric/l10n/l10n.dart';

final AppLocalizations l10nEn = lookupAppLocalizations(const Locale('en'));

Uint8List fontBytes(String face) =>
    File('assets/custom_fonts/Avenir-$face.ttf').readAsBytesSync();

ExportFonts testFonts() {
  pw.Font font(String face) =>
      pw.Font.ttf(ByteData.sublistView(fontBytes(face)));
  return ExportFonts(
    light: font('Light'),
    heavy: font('Heavy'),
    black: font('Black'),
  );
}

/// Records what would have been printed, shared or picked.
class FakeExportPlatform extends ExportPlatform {
  final shared = <({String filename, String mimeType, Uint8List bytes})>[];
  final sharedPdfs = <({String filename, Uint8List bytes})>[];
  final printed = <({String name, Uint8List bytes})>[];

  /// What the share sheet reports; false means the user dismissed it.
  bool shareCompletes = true;

  /// What the file picker returns; null means the user cancelled.
  ({String name, Uint8List bytes})? pickResult;

  @override
  Future<ExportFonts> loadFonts() async => testFonts();

  @override
  Future<void> printPdf({
    required String name,
    required Future<Uint8List> Function(PdfPageFormat paper) build,
  }) async => printed.add((name: name, bytes: await build(PdfPageFormat.a4)));

  @override
  Future<void> sharePdf({
    required Uint8List bytes,
    required String filename,
    Rect? origin,
  }) async => sharedPdfs.add((filename: filename, bytes: bytes));

  @override
  Future<bool> shareFile({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? subject,
    Rect? origin,
  }) async {
    shared.add((filename: filename, mimeType: mimeType, bytes: bytes));
    return shareCompletes;
  }

  @override
  Future<({String name, Uint8List bytes})?> pickBackupFile() async =>
      pickResult;
}

bool isPdf(Uint8List bytes) =>
    bytes.length > 1000 && String.fromCharCodes(bytes.take(5)) == '%PDF-';
