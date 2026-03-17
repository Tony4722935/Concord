import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:concord/l10n/app_strings.dart';

const int kAvatarAndIconMaxBytes = 10 * 1024 * 1024;
const Set<String> kAvatarAndIconAllowedExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
};

class CroppedAssetImage {
  const CroppedAssetImage({
    required this.data,
    required this.contentType,
    required this.fileExtension,
  });

  final Uint8List data;
  final String contentType;
  final String fileExtension;
}

Future<CroppedAssetImage?> pickAndCropSquareImage({
  required BuildContext context,
  required AppStrings strings,
  bool withCircleUi = true,
}) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked == null) {
    return null;
  }

  final extension = _normalizeFileExtension(picked.name, picked.path);
  if (!kAvatarAndIconAllowedExtensions.contains(extension)) {
    _showMessage(
      context,
      strings.t(
        'image_format_not_supported',
        fallback: 'Unsupported image format. Use PNG, JPG, WEBP, or GIF.',
      ),
    );
    return null;
  }

  final originalBytes = await picked.readAsBytes();
  if (originalBytes.isEmpty) {
    _showMessage(
      context,
      strings.t('image_empty', fallback: 'Image file is empty.'),
    );
    return null;
  }
  if (originalBytes.length > kAvatarAndIconMaxBytes) {
    _showMessage(
      context,
      strings.t(
        'image_too_large',
        fallback: 'Image is too large. Maximum file size is 10 MB.',
      ),
    );
    return null;
  }

  final cropped = await showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _SquareCropDialog(
      imageBytes: originalBytes,
      withCircleUi: withCircleUi,
      strings: strings,
    ),
  );
  if (cropped == null) {
    return null;
  }
  final normalized = _normalizeToPng(cropped);
  if (normalized == null) {
    _showMessage(
      context,
      strings.t(
        'failed_process_image',
        fallback: 'Failed to process image. Try another one.',
      ),
    );
    return null;
  }
  if (normalized.length > kAvatarAndIconMaxBytes) {
    _showMessage(
      context,
      strings.t(
        'image_too_large',
        fallback: 'Image is too large. Maximum file size is 10 MB.',
      ),
    );
    return null;
  }

  return CroppedAssetImage(
    data: normalized,
    contentType: 'image/png',
    fileExtension: 'png',
  );
}

class _SquareCropDialog extends StatefulWidget {
  const _SquareCropDialog({
    required this.imageBytes,
    required this.withCircleUi,
    required this.strings,
  });

  final Uint8List imageBytes;
  final bool withCircleUi;
  final AppStrings strings;

  @override
  State<_SquareCropDialog> createState() => _SquareCropDialogState();
}

class _SquareCropDialogState extends State<_SquareCropDialog> {
  final CropController _controller = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 560,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.strings.t('crop_image', fallback: 'Crop Image'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Crop(
                    image: widget.imageBytes,
                    controller: _controller,
                    onCropped: (result) {
                      if (!mounted) {
                        return;
                      }
                      switch (result) {
                        case CropSuccess(:final croppedImage):
                          Navigator.of(context).pop(croppedImage);
                        case CropFailure():
                          setState(() {
                            _cropping = false;
                          });
                      }
                    },
                    withCircleUi: widget.withCircleUi,
                    aspectRatio: 1,
                    maskColor: Colors.black54,
                    baseColor: Colors.black,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _cropping
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      widget.strings.t('cancel', fallback: 'Cancel'),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _cropping
                        ? null
                        : () {
                            setState(() {
                              _cropping = true;
                            });
                            _controller.crop();
                          },
                    child: Text(
                      _cropping
                          ? widget.strings.t('saving', fallback: 'Saving...')
                          : widget.strings.t('save', fallback: 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

String _normalizeFileExtension(String name, String path) {
  final fromName = _extensionFromPath(name);
  if (fromName != null) {
    return fromName;
  }
  return _extensionFromPath(path) ?? '';
}

String? _extensionFromPath(String input) {
  final index = input.lastIndexOf('.');
  if (index < 0 || index >= input.length - 1) {
    return null;
  }
  return input.substring(index + 1).toLowerCase().trim();
}

Uint8List? _normalizeToPng(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }
  final encoded = img.encodePng(decoded, level: 6);
  return Uint8List.fromList(encoded);
}
