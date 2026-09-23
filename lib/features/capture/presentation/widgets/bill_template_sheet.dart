import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/structured_template.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';

class BillTemplateSheet extends StatefulWidget {
  final BillTemplate? initialTemplate;

  const BillTemplateSheet({super.key, this.initialTemplate});

  /// Helper to show modal bottom sheet
  static Future<bool?> show(
    BuildContext context, {
    BillTemplate? initialTemplate,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BillTemplateSheet(initialTemplate: initialTemplate),
    );
  }

  @override
  State<BillTemplateSheet> createState() => _BillTemplateSheetState();
}

class _BillTemplateSheetState extends State<BillTemplateSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _consumerNumberController;
  late final TextEditingController _amountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _notesController;

  String _selectedBillType = 'Electricity';
  bool _isPaid = false;
  bool _isSaving = false;

  static const List<Map<String, dynamic>> _billTypes = [
    {'name': 'Electricity', 'icon': Icons.bolt_rounded},
    {'name': 'Gas', 'icon': Icons.local_fire_department_rounded},
    {'name': 'Internet', 'icon': Icons.wifi_rounded},
    {'name': 'Water', 'icon': Icons.water_drop_rounded},
    {'name': 'Telephone', 'icon': Icons.phone_android_rounded},
    {'name': 'Other', 'icon': Icons.receipt_long_rounded},
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTemplate;
    _consumerNumberController = TextEditingController(
      text: initial?.consumerNumber ?? '',
    );
    _amountController = TextEditingController(text: initial?.amount ?? '');
    _dueDateController = TextEditingController(
      text:
          initial?.dueDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
    if (initial != null) {
      _selectedBillType = initial.billType;
      _isPaid = initial.isPaid;
    }
  }

  @override
  void dispose() {
    _consumerNumberController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    DateTime initial = now;
    try {
      initial = DateFormat('yyyy-MM-dd').parse(_dueDateController.text);
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Select Bill Due Date',
    );
    if (picked != null) {
      setState(() {
        _dueDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  IconData _iconForBillType(String type) {
    final match = _billTypes.firstWhere(
      (b) => b['name'] == type,
      orElse: () => {'icon': Icons.receipt_long_rounded},
    );
    return match['icon'] as IconData;
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) return;

    final consumerNumber = _consumerNumberController.text.trim();
    final amount = _amountController.text.trim();
    final dueDate = _dueDateController.text.trim();
    final notes = _notesController.text.trim();

    setState(() => _isSaving = true);

    final template = BillTemplate(
      billType: _selectedBillType,
      consumerNumber: consumerNumber,
      amount: amount,
      dueDate: dueDate,
      isPaid: _isPaid,
      notes: notes.isNotEmpty ? notes : null,
    );

    final title = '$_selectedBillType Bill ($consumerNumber)';
    final content = template.toSerializedContent();
    final tags = [
      '#bill',
      '#utility',
      _selectedBillType.toLowerCase(),
      _isPaid ? '#paid' : '#unpaid',
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
                  ? 'Bill saved and organized!'
                  : 'Bill saved offline — ready for sync',
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
            content: Text('Failed to save bill: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
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
                const SizedBox(height: 14),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _iconForBillType(_selectedBillType),
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Save Utility / Bill',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Keep reference numbers and due dates organized',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Live Receipt Preview
                _buildLiveReceiptPreview(context),
                const SizedBox(height: 18),

                // Bill Type Horizontal Choice Chips
                Text(
                  'Bill Type',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _billTypes.map((b) {
                    final name = b['name'] as String;
                    final icon = b['icon'] as IconData;
                    final isSelected = _selectedBillType == name;
                    return InkWell(
                      onTap: () => setState(() => _selectedBillType = name),
                      borderRadius: BorderRadius.circular(100),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.inputFillOf(context),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.borderOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 14,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Consumer / Reference Number
                Text(
                  'Consumer / Reference Number',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _consumerNumberController,
                  decoration: _buildInputDecoration(
                    context,
                    hint: 'e.g. 08 11234 5678901 U',
                    icon: Icons.tag_rounded,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter consumer or reference number'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                // Amount & Due Date Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _amountController,
                            keyboardType: TextInputType.text,
                            decoration: _buildInputDecoration(
                              context,
                              hint: 'e.g. PKR 12,450',
                              icon: Icons.payments_outlined,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Due Date
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Due Date',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _dueDateController,
                            readOnly: true,
                            onTap: _pickDueDate,
                            decoration: _buildInputDecoration(
                              context,
                              hint: 'YYYY-MM-DD',
                              icon: Icons.calendar_month_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Payment Status Switch Card
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isPaid
                        ? const Color(0xFF10B981).withValues(alpha: 0.1)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isPaid
                          ? const Color(0xFF10B981).withValues(alpha: 0.3)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isPaid
                            ? Icons.check_circle_rounded
                            : Icons.pending_rounded,
                        color: _isPaid
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isPaid ? 'Bill Paid' : 'Payment Pending',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _isPaid
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B),
                              ),
                            ),
                            Text(
                              _isPaid
                                  ? 'Marked as completed'
                                  : 'Tap toggle when paid',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _isPaid,
                        activeTrackColor: const Color(0xFF10B981),
                        onChanged: (val) => setState(() => _isPaid = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Notes
                Text(
                  'Notes (Optional)',
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
                  decoration: _buildInputDecoration(
                    context,
                    hint: 'e.g. Paid via mobile banking app',
                    icon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 22),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveBill,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Save Bill to Memory',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveReceiptPreview(BuildContext context) {
    final consumerText = _consumerNumberController.text.trim().isNotEmpty
        ? _consumerNumberController.text.trim()
        : 'REF-00000000';
    final amountText = _amountController.text.trim().isNotEmpty
        ? _amountController.text.trim()
        : 'PKR 0.00';
    final dueText = _dueDateController.text.trim().isNotEmpty
        ? _dueDateController.text.trim()
        : 'YYYY-MM-DD';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForBillType(_selectedBillType),
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_selectedBillType Bill',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isPaid
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _isPaid ? 'PAID' : 'DUE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _isPaid
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amountText,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryOf(context),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Ref: $consumerText',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Due: $dueText',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
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
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.inputFillOf(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
