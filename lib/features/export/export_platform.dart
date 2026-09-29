import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:rubric/features/export/pdf_style.dart';
import 'package:share_plus/share_plus.dart';

/// The side effects of exporting: fonts, the print dialog, the share sheet
/// and the file picker. Everything that talks to the platform goes through
/// here so screens and actions can be tested with a fake.
class ExportPlatform {
  Future<ExportFonts>? _fonts;

  /// Loaded once, on first export; a failed load is retried next time.
  Future<ExportFonts> loadFonts() =>
      _fonts ??= ExportFonts.load(rootBundle).onError<Object>((error, stack) {
        _fonts = null;
        Error.throwWithStackTrace(error, stack);
      });

  /// Opens the system print dialog; [build] lays the document out for the
  /// paper the user picks.
  Future<void> printPdf({
    required String name,
    required Future<Uint8List> Function(PdfPageFormat paper) build,
  }) => Printing.layoutPdf(name: name, onLayout: build);

  Future<void> sharePdf({
    required Uint8List bytes,
    required String filename,
    Rect? origin,
  }) => Printing.sharePdf(bytes: bytes, filename: filename, bounds: origin);

  /// Writes [bytes] to a temporary file named [filename] and opens the share
  /// sheet for it. Returns false when the user dismissed the sheet.
  Future<bool> shareFile({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? subject,
    Rect? origin,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: filename)],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// Lets the user pick a backup file; null when they cancel.
  Future<({String name, Uint8List bytes})?> pickBackupFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  }
}

final exportPlatformProvider = Provider<ExportPlatform>(
  (ref) => ExportPlatform(),
);
