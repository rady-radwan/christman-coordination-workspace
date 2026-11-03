import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;

class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Lets the person choose one file (Windows: file dialog; phones: the system picker).
/// [extensions] limits the choice, e.g. ['xlsx']; empty = any file.
Future<PickedFile?> pickOneFile({List<String> extensions = const [], String label = 'Files'}) async {
  final groups = extensions.isEmpty
      ? const <fs.XTypeGroup>[]
      : [
          fs.XTypeGroup(
            label: label,
            extensions: extensions,
            mimeTypes: [
              for (final e in extensions)
                if (e == 'xlsx') 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              for (final e in extensions)
                if (e == 'pdf') 'application/pdf',
            ],
          ),
        ];
  final file = await fs.openFile(acceptedTypeGroups: groups);
  if (file == null) return null;
  return PickedFile(file.name, await file.readAsBytes());
}
