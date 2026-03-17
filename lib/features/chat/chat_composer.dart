import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSendText,
    required this.onSendImage,
  });

  final ValueChanged<String> onSendText;
  final ValueChanged<String> onSendImage;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (file == null) {
      return;
    }

    widget.onSendImage(file.path);
  }

  void _submitText() {
    widget.onSendText(_controller.text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Send image',
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(),
              decoration: const InputDecoration(
                hintText: 'Message',
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _submitText,
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
