import 'dart:typed_data';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../editor/markup_editor.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// The camera is offered on phones. On Windows, photos and screenshots come from files.
bool get cameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Lets the person take or choose photos, then opens each one in the markup editor.
/// Returns the finished JPEG images (skipping any they cancelled).
Future<List<Uint8List>> pickAndMarkUp(BuildContext context, {required bool camera}) async {
  final picker = ImagePicker();
  final results = <Uint8List>[];
  try {
    final List<XFile> files;
    if (camera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxPhotoSide.toDouble(),
        maxHeight: maxPhotoSide.toDouble(),
        imageQuality: 92,
      );
      files = shot == null ? const [] : [shot];
    } else {
      files = await picker.pickMultiImage(
        maxWidth: maxPhotoSide.toDouble(),
        maxHeight: maxPhotoSide.toDouble(),
        imageQuality: 92,
      );
    }
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      if (!context.mounted) break;
      final title = files.length > 1 ? 'Mark up photo ${i + 1} of ${files.length}' : 'Mark up photo';
      final done = await openMarkupEditor(context, bytes, title: title);
      if (done != null) results.add(done);
    }
  } catch (e) {
    if (context.mounted) showError(context, 'Could not open the photo: $e');
  }
  return results;
}

/// "Add photos" (and "Take photo" on phones) buttons.
class AddPhotoButtons extends StatelessWidget {
  const AddPhotoButtons({super.key, required this.onAdded, this.compact = false});
  final ValueChanged<List<Uint8List>> onAdded;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Future<void> pick(bool camera) async {
      final list = await pickAndMarkUp(context, camera: camera);
      if (list.isNotEmpty) onAdded(list);
    }

    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (cameraAvailable)
          IconButton(tooltip: 'Take photo', onPressed: () => pick(true), icon: const Icon(Icons.photo_camera_outlined)),
        IconButton(
          tooltip: cameraAvailable ? 'Add photos' : 'Add photos or screenshots',
          onPressed: () => pick(false),
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (cameraAvailable)
        OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Take Photo')),
      OutlinedButton.icon(
        onPressed: () => pick(false),
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
        label: Text(cameraAvailable ? 'Add Photos' : 'Add Photos / Screenshots'),
      ),
    ]);
  }
}

/// Shows a stored photo (from the server).
class RefImage extends StatelessWidget {
  const RefImage(this.photoRef, {super.key, this.fit = BoxFit.cover});
  final String photoRef;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    final c = CwColors.of(context);
    return FutureBuilder<ImageProvider>(
      future: api.image(photoRef),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            color: c.surface2,
            alignment: Alignment.center,
            child: snap.hasError
                ? Icon(Icons.broken_image_outlined, color: c.muted)
                : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Image(
          image: snap.data!,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(color: c.surface2, child: Icon(Icons.broken_image_outlined, color: c.muted)),
        );
      },
    );
  }
}

/// A photo in a form: either one already stored (ref) or a new one (bytes).
class FormPhoto {
  FormPhoto.stored(String this.ref) : bytes = null;
  FormPhoto.fresh(Uint8List this.bytes) : ref = null;
  final String? ref;
  final Uint8List? bytes;
}

/// Thumbnail grid for the item form: open, mark up again, remove.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos, required this.onChanged});
  final List<FormPhoto> photos;
  final ValueChanged<List<FormPhoto>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final api = context.read<AppState>().api;

    Future<void> remark(int i) async {
      final p = photos[i];
      try {
        final bytes = p.bytes ?? await api.photoBytes(p.ref!);
        if (!context.mounted) return;
        final done = await openMarkupEditor(context, bytes, title: 'Mark up photo ${i + 1}');
        if (done == null) return;
        final next = List.of(photos)..[i] = FormPhoto.fresh(done);
        onChanged(next);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (var i = 0; i < photos.length; i++)
        SizedBox(
          width: 132,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Material(
                  color: c.surface2,
                  child: InkWell(
                    onTap: () => remark(i),
                    child: photos[i].bytes != null
                        ? Image.memory(photos[i].bytes!, fit: BoxFit.cover)
                        : RefImage(photos[i].ref!),
                  ),
                ),
              ),
            ),
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => remark(i),
                  icon: const Icon(Icons.draw_outlined, size: 16),
                  label: const Text('Mark up'),
                ),
              ),
              IconButton(
                tooltip: 'Remove photo',
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(List.of(photos)..removeAt(i)),
                icon: Icon(Icons.delete_outline, size: 18, color: c.muted),
              ),
            ]),
          ]),
        ),
    ]);
  }
}

/// Full-screen zoomable photo viewer.
void showPhotoViewer(BuildContext context, List<String> refs, int start) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PhotoViewer(refs: refs, start: start),
  ));
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.refs, required this.start});
  final List<String> refs;
  final int start;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.start);
  late int _i = widget.start;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const Border(),
          title: Text('Photo ${_i + 1} of ${widget.refs.length}', style: const TextStyle(color: Colors.white)),
          actions: [
            if (widget.refs.length > 1) ...[
              IconButton(
                tooltip: 'Previous',
                onPressed: _i == 0 ? null : () => _pages.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: _i == widget.refs.length - 1
                    ? null
                    : () => _pages.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
        body: PageView.builder(
          controller: _pages,
          itemCount: widget.refs.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 6,
            child: Center(child: RefImage(widget.refs[i], fit: BoxFit.contain)),
          ),
        ),
      );
}

/// The item's photos on its page: a large photo, thumbnails, and actions.
class ItemGallery extends StatefulWidget {
  const ItemGallery({super.key, required this.refs, this.onMarkUp, this.onAdd, this.onRemove});
  final List<String> refs;

  /// Coordinators: mark up the shown photo again / add / remove photos.
  final Future<void> Function(int index)? onMarkUp;
  final VoidCallback? onAdd;
  final Future<void> Function(int index)? onRemove;

  @override
  State<ItemGallery> createState() => _ItemGalleryState();
}

class _ItemGalleryState extends State<ItemGallery> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final refs = widget.refs;
    if (_i >= refs.length) _i = 0;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: const Color(0xFF1A1A1A),
          child: InkWell(
            onTap: () => showPhotoViewer(context, refs, _i),
            child: AspectRatio(aspectRatio: 16 / 9, child: RefImage(refs[_i], fit: BoxFit.contain)),
          ),
        ),
        Container(
          color: c.surface2,
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: refs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => setState(() => _i = i),
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: i == _i ? c.accent : Colors.transparent, width: 2.5),
                      ),
                      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: RefImage(refs[i])),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${_i + 1} of ${refs.length}', style: TextStyle(fontSize: 13, color: c.muted)),
            IconButton(tooltip: 'Open full size', onPressed: () => showPhotoViewer(context, refs, _i), icon: const Icon(Icons.open_in_full, size: 20)),
            if (widget.onMarkUp != null)
              IconButton(tooltip: 'Mark up this photo', onPressed: () => widget.onMarkUp!(_i), icon: const Icon(Icons.draw_outlined, size: 20)),
            if (widget.onAdd != null)
              IconButton(tooltip: 'Add photos', onPressed: widget.onAdd, icon: const Icon(Icons.add_photo_alternate_outlined, size: 20)),
            if (widget.onRemove != null)
              IconButton(tooltip: 'Remove this photo', onPressed: () => widget.onRemove!(_i), icon: const Icon(Icons.delete_outline, size: 20)),
          ]),
        ),
      ]),
    );
  }
}

/// Small preview of a photo waiting to be sent with a reply.
class PendingPhoto extends StatelessWidget {
  const PendingPhoto({super.key, required this.bytes, required this.onRemove, this.size = 72});
  final Uint8List bytes;
  final VoidCallback onRemove;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, fit: BoxFit.cover)),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: const Color(0xCC1A1A1A),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 15, color: Colors.white, semanticLabel: 'Remove photo'),
                ),
              ),
            ),
          ),
        ]),
      );
}
