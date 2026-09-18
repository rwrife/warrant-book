// Warrant Book — attachment picker contract (issue #6).
//
// Pure Dart contract between the UI and whatever file-selection surface
// backs it: production drives image_picker/file_picker; widget tests
// inject a stub. Lives on its own so AppScope can reference it without
// importing Flutter-UI code.

/// A file the user chose to attach (path on disk + display name).
class PickedAttachment {
  const PickedAttachment({required this.path, required this.displayName});

  final String path;
  final String displayName;
}

abstract interface class AttachmentPicker {
  /// Photo from camera/gallery; null when the user cancels.
  Future<PickedAttachment?> pickImage();

  /// Document (PDF) from the files UI; null when the user cancels.
  Future<PickedAttachment?> pickDocument();
}

/// Hands an exported/shared file to the OS. Production wraps share_plus;
/// tests record calls.
typedef FileShareCallback = Future<void> Function(String path);
