import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file name safe on every platform: "Dues ageing 1 Nov - 16 Nov.pdf".
String safePdfName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[–—]'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${cleaned.isEmpty ? 'document' : cleaned}.pdf';
}

/// Shares a PDF under a readable name. Android ignores names of in-memory
/// files, so the bytes are written to the app's temporary folder first.
Future<void> sharePdf(
  Uint8List bytes, {
  required String title,
  String? text,
}) async {
  final folder = await getTemporaryDirectory();
  final file = File('${folder.path}/${safePdfName(title)}');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      text: text,
    ),
  );
}

/// Shares any file under [fileName], written to the temporary folder first.
Future<void> shareFile(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
  String? text,
}) async {
  final folder = await getTemporaryDirectory();
  final file = File('${folder.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      text: text,
    ),
  );
}
