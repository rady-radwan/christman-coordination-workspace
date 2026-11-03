import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// A published version of the app (from version.json next to the installers).
class AppRelease {
  AppRelease({required this.version, this.notes = const [], this.windowsUrl, this.androidUrl, this.androidOlderUrl, this.published});

  final String version;
  final List<String> notes;
  final String? windowsUrl;
  final String? androidUrl;
  final String? androidOlderUrl;
  final DateTime? published;

  /// The download for this device.
  String? get url => Platform.isWindows ? windowsUrl : (Platform.isAndroid ? androidUrl : null);

  factory AppRelease.fromJson(Map<String, dynamic> j) {
    String? link(Object? v) => v is String && v.isNotEmpty ? (v.startsWith('http') ? v : '$releaseBaseUrl/$v') : null;
    return AppRelease(
      version: (j['version'] ?? '') as String,
      notes: j['notes'] is List ? [for (final n in j['notes'] as List) '$n'] : const [],
      windowsUrl: link(j['windows']),
      androidUrl: link(j['android']),
      androidOlderUrl: link(j['android_older']),
      published: DateTime.tryParse('${j['published'] ?? ''}')?.toLocal(),
    );
  }
}

/// 1 when [a] is newer than [b], -1 when older, 0 when the same ("0.10.0" > "0.9.3").
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split('+').first.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p > q ? 1 : -1;
  }
  return 0;
}

/// The newest published version, or null when it cannot be checked (offline…).
Future<AppRelease?> fetchLatestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('$releaseBaseUrl/version.json?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'));
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    if (j is! Map<String, dynamic>) return null;
    final r = AppRelease.fromJson(j);
    return r.version.isEmpty ? null : r;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Windows: downloads the installer (reporting 0..1 progress), starts it and returns.
/// The caller then closes the app so the installer can replace it.
Future<void> downloadAndStartInstaller(String url, void Function(double progress) onProgress) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode}). Try the download link instead.');
    final dir = await getTemporaryDirectory();
    final name = Uri.parse(url).pathSegments.last;
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final sink = file.openWrite();
    final total = res.contentLength;
    var got = 0;
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    await Process.start(file.path, const [], mode: ProcessStartMode.detached);
  } finally {
    client.close(force: true);
  }
}

/// Opens the download link in the browser (phones, or when the in-app download fails).
Future<bool> openDownloadLink(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
