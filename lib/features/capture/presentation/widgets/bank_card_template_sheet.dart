import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/structured_template.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';

class BankCardTemplateSheet extends StatefulWidget {
  final BankCardTemplate? initialTemplate;

  const BankCardTemplateSheet({super.key, this.initialTemplate});

  /// Helper to show modal bottom sheet
  static Future<bool?> show(
    BuildContext context, {
    BankCardTemplate? initialTemplate,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: Colors.transparent,
      builder: (_) => BankCardTemplateSheet(initialTemplate: initialTemplate),
    );
  }

  @override
  State<BankCardTemplateSheet> createState() => _BankCardTemplateSheetState();
}

class _BankCardTemplateSheetState extends State<BankCardTemplateSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _cardholderController;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _expiryController;
  late final TextEditingController _notesController;

  String _selectedCardType = 'Visa';
  bool _isSaving = false;

  static const List<String> _popularBanks = [
    'Meezan Bank',
    'HBL',
    'Bank Alfalah',
    'MCB',
    'Standard Chartered',
    'UBL',
    'Chase',
    'Bank of America',
    'Wells Fargo',
    'Other Bank',
  ];

  static const List<String> _cardTypes = [
    'Visa',
    'Mastercard',
    'PayPak',
    'American Express',
    'UnionPay',
    'Debit Card',
    'Credit Card',
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTemplate;
    _cardholderController = TextEditingController(
      text: initial?.cardholderName ?? '',
    );
    _cardNumberController = TextEditingController(
      text: initial?.cardNumber ?? '',
    );
    _bankNameController = TextEditingController(
      text: initial?.bankName ?? 'Meezan Bank',
    );
    _expiryController = TextEditingController(text: initial?.expiryDate ?? '');
    _notesController = TextEditingController(text: initial?.notes ?? '');
    if (initial != null && _cardTypes.contains(initial.cardType)) {
      _selectedCardType = initial.cardType;
    }
  }

  @override
  void dispose() {
    _cardholderController.dispose();
    _cardNumberController.dispose();
    _bankNameController.dispose();
    _expiryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onCardNumberChanged(String val) {
    final clean = val.replaceAll(RegExp(r'\D'), '');
    if (clean.length > 16) return;
    final formatted = BankCardTemplate.formatCardNumber(clean);
    if (formatted != val) {
      _cardNumberController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    setState(() {});
  }

  void _onExpiryChanged(String val) {
    final clean = val.replaceAll(RegExp(r'\D'), '');
    if (clean.length > 4) return;
    String formatted = clean;
    if (clean.length >= 3) {
      formatted = '${clean.substring(0, 2)}/${clean.substring(2)}';
    }
    if (formatted != val) {
      _expiryController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    setState(() {});
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 365 * 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 15)),
      helpText: 'Select Card Expiry',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: const Color(0xFF0F3E32),
            secondary: const Color(0xFF0F3E32),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final month = picked.month.toString().padLeft(2, '0');
      final year = (picked.year % 100).toString().padLeft(2, '0');
      setState(() {
        _expiryController.text = '$month/$year';
      });
    }
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'add':
        setState(() {
          _formKey.currentState?.reset();
          _cardholderController.clear();
          _cardNumberController.clear();
          _bankNameController.text = 'Meezan Bank';
          _expiryController.clear();
          _notesController.clear();
          _selectedCardType = 'Visa';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Form cleared — enter a new card'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;
      case 'delete':
        _confirmDeleteTemplate();
        break;
      case 'close':
        Navigator.of(context).pop();
        break;
    }
  }

  Future<void> _confirmDeleteTemplate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Template'),
        content: const Text(
          'Are you sure you want to delete this card template? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    final cardholder = _cardholderController.text.trim();
    final cardNumber = _cardNumberController.text.trim();
    final bankName = _bankNameController.text.trim();
    final expiry = _expiryController.text.trim();
    final notes = _notesController.text.trim();

    setState(() => _isSaving = true);

    final template = BankCardTemplate(
      cardholderName: cardholder,
      cardNumber: cardNumber,
      bankName: bankName,
      cardType: _selectedCardType,
      expiryDate: expiry,
      notes: notes.isNotEmpty ? notes : null,
    );

    final title = '$bankName $_selectedCardType (•••• ${template.last4})';
    final content = template.toMarkdownBody();
    final metadata = template.toJson();
    final tags = [
      '#card',
      '#finance',
      '#bank',
      bankName.toLowerCase().replaceAll(RegExp(r'\s+'), ''),
      _selectedCardType.toLowerCase(),
    ];

    try {
      context.read<CaptureBloc>().add(
        AddMemoryEvent(
          title: title,
          content: content,
          category: AppStrings.categoryFinance,
          tags: tags,
          mediaUrl: null,
          aiStatus: 'processed',
          metadata: metadata,
        ),
      );

      bool isOnline = false;
      try {
        isOnline = Supabase.instance.client.auth.currentUser != null;
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOnline
                  ? 'Bank card saved securely!'
                  : 'Bank card saved offline — encrypted on device',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save card: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: const Color(0xFF0F3E32),
        secondary: const Color(0xFF0F3E32),
      ),
      highlightColor: const Color(0xFF0F3E32).withValues(alpha: 0.12),
      splashColor: const Color(0xFF0F3E32).withValues(alpha: 0.12),
    );

    return Theme(
      data: sheetTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF0F3E32),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Pinned fixed green header (does not scroll)
              Container(
                width: double.infinity,
                color: const Color(0xFF0F3E32),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).viewPadding.top > 0
                      ? MediaQuery.of(context).viewPadding.top + 10
                      : 44.0,
                  bottom: 14,
                  left: 16,
                  right: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.credit_card,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Save Bank Card',
                        style: const TextStyle(
                  color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Colors.white,
                        size: 24,
                      ),
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: _handleMenuSelection,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'add',
                          child: Row(
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                color: Color(0xFF0F3E32),
                              ),
                              SizedBox(width: 10),
                              Text('Add New Template'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red),
                              SizedBox(width: 10),
                              Text(
                                'Delete Current Template',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'close',
                          child: Row(
                            children: [
                              Icon(Icons.close, color: Color(0xFF0F3E32)),
                              SizedBox(width: 10),
                              Text('Close Sheet'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Scrollable form body only
              Expanded(
                child: Container(
                  color: isDark ? const Color(0xFF162320) : const Color(0xFFFBFBF9),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom:
                          bottomInset +
                          (MediaQuery.of(context).viewPadding.bottom > 0
                              ? MediaQuery.of(context).viewPadding.bottom + 32
                              : 32),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Live Card Preview
                            _buildLiveCardPreview(isDark),
                            const SizedBox(height: 18),

                            // Bank Name Dropdown / Input
                            Text(
                              'Bank Name',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildPickerField(
                              context,
                              hint: 'Select Bank',
                              icon: Icons.account_balance_rounded,
                              value:
                                  _popularBanks.contains(
                                    _bankNameController.text,
                                  )
                                  ? _bankNameController.text
                                  : 'Other Bank',
                              onTap: () async {
                                final current =
                                    _popularBanks.contains(
                                      _bankNameController.text,
                                    )
                                    ? _bankNameController.text
                                    : 'Other Bank';
                                final result = await _showPickerSheet(
                                  title: 'Select Bank',
                                  items: _popularBanks,
                                  selected: current,
                                );
                                if (result != null) {
                                  setState(() {
                                    _bankNameController.text =
                                        result == 'Other Bank' ? '' : result;
                                  });
                                }
                              },
                            ),
                            if (!_popularBanks.contains(
                              _bankNameController.text,
                            )) ...[
                              const SizedBox(height: 8),
                              TextFormField(
                            controller: _bankNameController,
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  hint: 'Enter custom bank name',
                                  icon: Icons.edit_note_rounded,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Please enter bank name'
                                    : null,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                            const SizedBox(height: 14),

                            // Cardholder Name
                            Text(
                              'Cardholder Name',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                            controller: _cardholderController,
                              textCapitalization: TextCapitalization.words,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildInputDecoration(
                                context,
                                hint: 'e.g. JOHN',
                                icon: Icons.person_outline_rounded,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Please enter cardholder name'
                                  : null,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 14),

                            // Card Number
                            Text(
                              'Card Number',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                            controller: _cardNumberController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildInputDecoration(
                                context,
                                hint: '•••• •••• •••• 1234',
                                icon: Icons.numbers_rounded,
                              ),
                              validator: (v) {
                                final clean = (v ?? '').replaceAll(
                                  RegExp(r'\D'),
                                  '',
                                );
                                if (clean.length < 4) {
                                  return 'Enter at least the last 4 digits of your card';
                                }
                                return null;
                              },
                              onChanged: _onCardNumberChanged,
                            ),
                            const SizedBox(height: 14),

                            // Expiry Date & Card Type Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Expiry Date
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Expiry (MM/YY)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _expiryController,
                                        keyboardType: TextInputType.number,
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: _buildInputDecoration(
                                          context,
                                          hint: 'MM/YY',
                                          icon: Icons.calendar_today_rounded,
                                          suffixIcon: IconButton(
                                            icon: const Icon(
                                              Icons.event_rounded,
                                              size: 18,
                                              color: Color(0xFF0F3E32),
                                            ),
                                            onPressed: _pickExpiryDate,
                                          ),
                                        ),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                            ? 'Required'
                                            : null,
                                        onChanged: _onExpiryChanged,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Card Type Dropdown
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Card Type',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _buildPickerField(
                                        context,
                                        hint: 'Type',
                                        icon: Icons.payment_rounded,
                                        value: _selectedCardType,
                                        onTap: () async {
                                          final result = await _showPickerSheet(
                                            title: 'Select Card Type',
                                            items: _cardTypes,
                                            selected: _selectedCardType,
                                          );
                                          if (result != null) {
                                            setState(
                                              () => _selectedCardType = result,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Notes / Branch Details
                            Text(
                              'Notes / Branch Details (Optional)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                            controller: _notesController,
                              maxLines: 2,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildInputDecoration(
                                context,
                                hint:
                                    'e.g. Salary account branch, ATM pin stored in head',
                                icon: Icons.notes_rounded,
                              ),
                            ),
                            const SizedBox(height: 22),

                            // Submit Button
                            Container(
                              padding: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 12,
                                bottom:
                                    MediaQuery.of(context).viewPadding.bottom > 0
                                        ? MediaQuery.of(
                                            context,
                                          ).viewPadding.bottom +
                                            8
                                        : 16,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _saveCard,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F3E32),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.save_rounded, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Save Card to Memory',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveCardPreview(bool isDark) {
    final bankText = _bankNameController.text.trim().isNotEmpty
        ? _bankNameController.text.trim()
        : 'Bank Name';
    final cardholderText = _cardholderController.text.trim().isNotEmpty
        ? _cardholderController.text.trim().toUpperCase()
        : 'CARDHOLDER NAME';
    final rawNumber = _cardNumberController.text.trim();
    final numberText = rawNumber.isNotEmpty
        ? BankCardTemplate.maskCardNumber(rawNumber)
        : '•••• •••• •••• ••••';
    final expiryText = _expiryController.text.trim().isNotEmpty
        ? _expiryController.text.trim()
        : 'MM/YY';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                bankText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedCardType.toUpperCase(),
                  style: const TextStyle(
                  color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 34,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2B755),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.nfc_rounded,
                  color: Colors.black38,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            numberText,
            style: const TextStyle(
                  color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CARDHOLDER',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cardholderText,
                      style: const TextStyle(
                  color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'EXPIRES',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expiryText,
                    style: const TextStyle(
                  color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      prefixIcon: Icon(icon, size: 20, color: isDark ? Colors.white70 : const Color(0xFF0F3E32)),
      suffixIcon: suffixIcon,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade600),
      filled: true,
      fillColor: isDark ? const Color(0xFF1F2F2B) : Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0F3E32), width: 1.5),
      ),
    );
  }

  Widget _buildPickerField(
    BuildContext context, {
    required String hint,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: _buildInputDecoration(
          context,
          hint: hint,
          icon: icon,
          suffixIcon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF0F3E32),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<String?> _showPickerSheet({
    required String title,
    required List<String> items,
    required String selected,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F3E32),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = item == selected;
                      return ListTile(
                        onTap: () => Navigator.of(sheetContext).pop(item),
                        tileColor: isSelected
                            ? const Color(0xFF0F3E32).withValues(alpha: 0.08)
                            : null,
                        title: Text(
                          item,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF0F3E32)
                                : const Color(0xFF1E293B),
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF0F3E32),
                              )
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}











