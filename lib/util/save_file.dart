import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sp;
import 'package:url_launcher/url_launcher.dart';

/// Gives a generated file (e.g. meeting minutes PDF) to the person.
/// Windows: asks where to save it, then opens it. Phones: opens the share menu
/// (Save to Files / Drive, email, Teams…).
/// Returns a short message for the screen, or null when they cancelled.
Future<String?> saveOrShareFile(Uint8List bytes, String fileName, {String mimeType = 'application/pdf'}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await sp.Share.shareXFiles([sp.XFile(file.path, mimeType: mimeType, name: fileName)], subject: fileName);
    return null;
  }
  final ext = fileName.contains('.') ? fileName.split('.').last : 'pdf';
  final location = await fs.getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [fs.XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
  );
  if (location == null) return null;
  var path = location.path;
  if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
  await File(path).writeAsBytes(bytes, flush: true);
  await launchUrl(Uri.file(path));
  return 'Saved $path';
}

/// Removes characters Windows does not allow in file names.
String safeFileName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-').replaceAll(RegExp(r'\s+'), ' ').trim();
