// Warrant Book — attachments UI (issue #6).
//
// Receipt documents for one item: attach an image (camera/gallery) or a
// PDF via an explicit user action, preview images inline, tap any
// attachment to share/open it, and delete individual attachments. The
// bytes themselves live in the content-addressed AttachmentStore behind
// [DataLifecycleService] — this file only wires pickers to it.
//
// Pickers are injected ([AttachmentPicker]) so widget tests can drive the
// flow with fixture files; production uses [PlatformAttachmentPicker].

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_scope.dart';
import '../../data/lifecycle/data_lifecycle_service.dart';
import '../../domain/models/purchase_item.dart';
import '../../l10n/generated/app_localizations.dart';
import 'attachment_picker.dart';

/// Production picker: image_picker for photos, file_picker for PDFs.
class PlatformAttachmentPicker implements AttachmentPicker {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Future<PickedAttachment?> pickImage() async {
    // ImageSource.gallery avoids the camera permission entirely; the app
    // never requests camera access (privacy contract, README).
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return PickedAttachment(path: file.path, displayName: file.name);
  }

  @override
  Future<PickedAttachment?> pickDocument() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty) return null;
    final file = files.first;
    final path = file.path;
    if (path == null) return null;
    return PickedAttachment(path: path, displayName: file.name);
  }
}

/// Shows the "add attachment" source sheet. Returns the picked file or
/// null. Kept separate from the widget so tests can invoke the flow with
/// an injected picker via [AttachmentSection] directly.
Future<PickedAttachment?> showAttachmentSourceSheet(
  BuildContext context,
  AttachmentPicker picker,
) async {
  final l10n = AppLocalizations.of(context);
  final source = await showModalBottomSheet<_AttachmentSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('attachPhotoOption'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.attachPhotoAction),
            onTap: () =>
                Navigator.of(sheetContext).pop(_AttachmentSource.photo),
          ),
          ListTile(
            key: const Key('attachPdfOption'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.attachPdfAction),
            onTap: () =>
                Navigator.of(sheetContext).pop(_AttachmentSource.document),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return switch (source) {
    _AttachmentSource.photo => picker.pickImage(),
    _AttachmentSource.document => picker.pickDocument(),
  };
}

enum _AttachmentSource { photo, document }

/// Attachments block of the detail screen.
class AttachmentSection extends StatefulWidget {
  const AttachmentSection({
    required this.item,
    required this.onChange,
    this.picker,
    this.shareOpen,
    super.key,
  });

  final PurchaseItem item;

  /// Called after a successful attach/delete so the page reloads.
  final Future<void> Function() onChange;

  final AttachmentPicker? picker;

  /// Overridable for tests: shares/opens an attachment file.
  final Future<void> Function(String absolutePath, String name)? shareOpen;

  @override
  State<AttachmentSection> createState() => _AttachmentSectionState();
}

class _AttachmentSectionState extends State<AttachmentSection> {
  late final AttachmentPicker _picker = widget.picker ??
      AppScope.read(context).attachmentPicker ??
      PlatformAttachmentPicker();
  bool _busy = false;
  String? _error;

  DataLifecycleService? get _lifecycle => AppScope.read(context).lifecycle;

  Future<void> _attach() async {
    if (_busy) return;
    final lifecycle = _lifecycle;
    if (lifecycle == null) return;
    final picked = await showAttachmentSourceSheet(context, _picker);
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await lifecycle.attachToFile(
        itemId: widget.item.id,
        sourcePath: picked.path,
        displayName: picked.displayName,
      );
      if (updated == null) {
        if (mounted) setState(() => _error = null);
        return;
      }
      await widget.onChange();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AttachmentRef ref) async {
    if (_busy) return;
    final lifecycle = _lifecycle;
    if (lifecycle == null) return;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteAttachmentTitle),
        content: Text(l10n.deleteAttachmentMessage(ref.displayName ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirmDeleteAttachmentButton'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await lifecycle.detachAttachment(
        itemId: widget.item.id,
        relativePath: ref.relativePath,
      );
      await widget.onChange();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(AttachmentRef ref) async {
    final scope = AppScope.read(context);
    final lifecycle = scope.lifecycle;
    if (lifecycle == null) return;
    final absolutePath =
        lifecycle.attachmentAbsolutePath(ref.relativePath);
    final share = widget.shareOpen ??
        (scope.fileSharer == null
            ? _defaultShare
            : (path, name) => scope.fileSharer!(path));
    try {
      await share(absolutePath, ref.displayName ?? ref.relativePath);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  static Future<void> _defaultShare(String path, String name) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lifecycle = AppScope.of(context).lifecycle;
    final attachments = widget.item.attachments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.attachmentsSection,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              key: const Key('addAttachmentButton'),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_link),
              tooltip: l10n.addAttachment,
              onPressed: lifecycle == null || _busy ? null : _attach,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            key: const Key('attachmentError'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (attachments.isEmpty)
          Text(l10n.emptyAttachments,
              style: Theme.of(context).textTheme.bodyMedium)
        else
          for (final ref in attachments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _AttachmentTile(
                ref: ref,
                absolutePath: lifecycle?.attachmentAbsolutePath(
                      ref.relativePath,
                    ) ??
                    ref.relativePath,
                onOpen: () => unawaited(_open(ref)),
                onDelete: () => unawaited(_delete(ref)),
              ),
            ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.ref,
    required this.absolutePath,
    required this.onOpen,
    required this.onDelete,
  });

  final AttachmentRef ref;
  final String absolutePath;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  bool get _isImage {
    final lower =
        (ref.displayName ?? ref.relativePath).toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.displayName ?? ref.relativePath;
    final file = File(absolutePath);
    final missing = !kIsWeb && !_fileExists(file);
    return ListTile(
      key: Key('attachmentTile-${ref.relativePath}'),
      contentPadding: EdgeInsets.zero,
      leading: _isImage && !missing
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              // Inline preview (issue #6 acceptance): real bytes, decoded
              // at tile size so widget tests and device memory both cope.
              child: Image.file(
                file,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            )
          : Icon(missing
              ? Icons.error_outline
              : Icons.picture_as_pdf_outlined),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: missing ? Text(AppLocalizations.of(context).attachmentMissing) : null,
      onTap: onOpen,
      trailing: IconButton(
        key: Key('deleteAttachment-${ref.relativePath}'),
        icon: const Icon(Icons.delete_outline),
        tooltip: AppLocalizations.of(context).delete,
        onPressed: onDelete,
      ),
    );
  }

  /// File existence is a cheap stat on the file service; widget tests use
  /// the real (temp-dir) filesystem so this is deterministic.
  static bool _fileExists(File file) {
    try {
      return file.existsSync();
    } on Object {
      return false;
    }
  }
}
