import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/link_metadata_extractor.dart';

class AddLinkBottomSheet extends StatefulWidget {
  final String? initialUrl;

  const AddLinkBottomSheet({
    super.key,
    this.initialUrl,
  });

  static Future<String?> show(BuildContext context, {String? initialUrl}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddLinkBottomSheet(initialUrl: initialUrl),
    );
  }

  @override
  State<AddLinkBottomSheet> createState() => _AddLinkBottomSheetState();
}

class _AddLinkBottomSheetState extends State<AddLinkBottomSheet> {
  late final TextEditingController _urlController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    _urlController.addListener(_onTextChanged);

    if (widget.initialUrl == null || widget.initialUrl!.isEmpty) {
      _checkClipboard();
    }
  }

  void _onTextChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        final error = LinkMetadataExtractor.validateUrl(text);
        if (error == null && mounted && _urlController.text.isEmpty) {
          setState(() {
            _urlController.text = text;
            _urlController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: text.length,
            );
          });
        }
      }
    } catch (_) {
      // Clipboard access failure fallback
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        setState(() {
          _urlController.text = text;
          _urlController.selection = TextSelection(
            baseOffset: text.length,
            extentOffset: text.length,
          );
          _errorMessage = null;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clipboard is empty.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to read clipboard.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _onSubmit() {
    final rawUrl = _urlController.text.trim();
    final error = LinkMetadataExtractor.validateUrl(rawUrl);
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    Navigator.of(context).pop(rawUrl);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onTextChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + viewInsetsBottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceTintOf(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Web Link',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Save and organize an article, website, or reference',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // URL Input Field
            Container(
              decoration: BoxDecoration(
                color: AppColors.toggleBackgroundOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _errorMessage != null
                      ? AppColors.errorText
                      : AppColors.borderOf(context),
                  width: _errorMessage != null ? 1.4 : 1.0,
                ),
              ),
              child: TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onSubmit(),
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimaryOf(context),
                ),
                decoration: InputDecoration(
                  hintText: 'https://example.com/article',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  prefixIcon: const Icon(
                    Icons.public_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  suffixIcon: _urlController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          color: AppColors.textSecondary,
                          onPressed: () {
                            _urlController.clear();
                            setState(() => _errorMessage = null);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),

            // Inline Validation Error
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: AppColors.errorText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.errorText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Paste from clipboard shortcut
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(
                  Icons.content_paste_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                label: const Text(
                  'Paste from Clipboard',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
