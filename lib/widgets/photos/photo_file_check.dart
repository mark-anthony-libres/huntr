/// Quick checks on a picked file before it's uploaded. The backend checks
/// again, properly; these just give faster feedback.
library;

enum ImageFileType { jpeg, png, webp, gif, other }

/// What the file really is, from its first bytes (not its name).
ImageFileType detectImageType(List<int> bytes) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith([0xFF, 0xD8, 0xFF])) return ImageFileType.jpeg;
  if (startsWith([0x89, 0x50, 0x4E, 0x47])) return ImageFileType.png;
  if (startsWith([0x47, 0x49, 0x46, 0x38])) return ImageFileType.gif; // "GIF8"
  if (startsWith([0x52, 0x49, 0x46, 0x46]) && // "RIFF....WEBP"
      startsWith([0x57, 0x45, 0x42, 0x50], 8)) {
    return ImageFileType.webp;
  }
  return ImageFileType.other;
}

/// MP4 and MOV files start with an `ftyp` box (the backend checks properly).
bool isVideoFile(List<int> bytes) =>
    bytes.length >= 12 &&
    bytes[4] == 0x66 && // "ftyp"
    bytes[5] == 0x74 &&
    bytes[6] == 0x79 &&
    bytes[7] == 0x70;

/// Why the picked video can't be used, or null if it looks fine.
String? checkPickedVideo(List<int> bytes, {required int maxBytes}) {
  if (bytes.length > maxBytes) {
    return 'The video is too large. The maximum is '
        '${maxBytes ~/ (1024 * 1024)} MB.';
  }
  return null;
}

/// Why the picked file can't be used, or null if it looks fine.
String? checkPickedPhoto(List<int> bytes, {required int maxBytes}) {
  if (bytes.isEmpty) return 'The file is empty.';
  if (bytes.length > maxBytes) {
    return 'The photo is too large. The maximum is '
        '${maxBytes ~/ (1024 * 1024)} MB.';
  }
  return switch (detectImageType(bytes)) {
    ImageFileType.gif =>
      "GIFs aren't supported. Please choose a JPEG, PNG or WebP photo.",
    ImageFileType.other =>
      'Unsupported image type. Please choose a JPEG, PNG or WebP photo.',
    _ => null,
  };
}
