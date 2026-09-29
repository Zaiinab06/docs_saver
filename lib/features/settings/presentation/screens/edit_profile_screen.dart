import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/profile_notifier.dart';

class EditProfileScreen extends StatefulWidget {
  final String initialName;
  final String initialEmail;
  final File? initialProfileImage;

  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialEmail,
    this.initialProfileImage,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late String _userEmail;
  File? _profileImageFile;
  final ImagePicker _imagePicker = ImagePicker();

  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _userEmail = widget.initialEmail;
    _profileImageFile = widget.initialProfileImage;
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(source: source);
      if (pickedFile != null && mounted) {
        setState(() {
          _profileImageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('[EditProfile] Error picking image: $e');
    }
  }

  void _showImagePickerModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCardBackground : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSubtleBorder : AppColors.subtleBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.camera_alt, color: isDark ? AppColors.periwinkle300 : AppColors.primary),
                title: Text('Take Photo', style: TextStyle(color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: isDark ? AppColors.periwinkle300 : AppColors.primary),
                title: Text('Choose from Gallery', style: TextStyle(color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_profileImageFile != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.errorText),
                  title: const Text('Remove Photo', style: TextStyle(color: AppColors.errorText)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _profileImageFile = null;
                    });
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _getInitial() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return 'U';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : const Color(0xFFFBFBF9);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: Column(
          children: [
            // 1. App Header
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).viewPadding.top + 12,
                bottom: 16,
                left: 16,
                right: 16,
              ),
              color: const Color(0xFF0F3E32),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context, _profileImageFile),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    // 2. Center Avatar Section
                    Center(
                      child: GestureDetector(
                        onTap: _showImagePickerModal,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                                border: Border.all(
                                  color: isDark ? AppColors.darkSubtleBorder : Colors.white,
                                  width: 4,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 52,
                                backgroundColor: isDark
                                    ? AppColors.darkCardBackground
                                    : Colors.grey.shade100,
                                backgroundImage: _profileImageFile != null
                                    ? FileImage(_profileImageFile!)
                                    : null,
                                child: _profileImageFile == null
                                    ? Text(
                                        _getInitial(),
                                        style: TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? AppColors.periwinkle300 : const Color(0xFF0F3E32),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F3E32),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? AppColors.darkBackground : bgColor,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // 3. Clean & Modern Rounded Input Fields
                    // Full Name Field
                    Text(
                      'Full Name',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF0F3E32)),
                        filled: true,
                        fillColor: isDark ? AppColors.darkCardBackground : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), 
                          borderSide: BorderSide(color: isDark ? AppColors.darkSubtleBorder : Colors.grey.shade300)
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), 
                          borderSide: BorderSide(color: isDark ? AppColors.darkSubtleBorder : Colors.grey.shade300)
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), 
                          borderSide: const BorderSide(color: Color(0xFF0F3E32), width: 1.5)
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Email Field (Read-only)
                    Text(
                      'Email Address',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: _userEmail,
                      readOnly: true,
                      enabled: false,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? AppColors.darkTextSecondary : Colors.grey.shade600,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.mail_outline, color: isDark ? AppColors.darkTextSecondary : Colors.grey.shade500),
                        suffixIcon: Icon(Icons.lock_outline, color: isDark ? AppColors.darkTextSecondary : Colors.grey.shade400, size: 20),
                        filled: true,
                        fillColor: isDark ? AppColors.darkBackground.withValues(alpha: 0.5) : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), 
                          borderSide: BorderSide(color: isDark ? AppColors.darkSubtleBorder : Colors.grey.shade200)
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), 
                          borderSide: BorderSide(color: isDark ? AppColors.darkSubtleBorder : Colors.grey.shade200)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Bottom "Save Profile" Button
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      final newName = _nameController.text.trim();
                      if (newName.isNotEmpty) {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('user_full_name', newName);
                          // Update global notifier
                          ProfileNotifier.nameNotifier.value = newName;
                          
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Profile updated successfully!')),
                            );
                            Navigator.pop(context, _profileImageFile);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to update profile: $e')),
                            );
                          }
                        }
                      } else {
                        // Just pop if empty or handle as needed
                        Navigator.pop(context, _profileImageFile);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F3E32),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Save Profile',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
