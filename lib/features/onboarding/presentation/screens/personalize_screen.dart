import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../main.dart';

class PersonalizeOption {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;

  const PersonalizeOption({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class PersonalizeScreen extends StatefulWidget {
  const PersonalizeScreen({super.key});

  @override
  State<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends State<PersonalizeScreen> {
  // Design Tokens
  static const Color primaryColor = Color(0xFF00B4D8);
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00B4D8), Color(0xFF0096C7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color backgroundColor = Color(0xFFFFFFFF);
  static const Color textPrimaryColor = Color(0xFF1A1A1A);
  static const Color textSecondaryColor = Color(0xFF8A8A8A);
  static const Color lightCyanTint = Color(0xFFEAFAFD);
  static const Color inactiveBorderColor = Color(0xFFF1F5F9);
  static const Color indicatorBorderColor = Color(0xFFCBD5E1);

  final Set<String> _selectedOptionIds = {};

  static const List<PersonalizeOption> _options = [
    PersonalizeOption(
      id: 'work',
      icon: Icons.work_outline_rounded,
      title: 'Work & productivity',
      subtitle: 'Projects, meetings, research, and professional notes',
    ),
    PersonalizeOption(
      id: 'personal',
      icon: Icons.favorite_border_rounded,
      title: 'Personal life',
      subtitle: 'Ideas, memories, goals, and things that inspire you',
    ),
    PersonalizeOption(
      id: 'learning',
      icon: Icons.school_outlined,
      title: 'Learning & growth',
      subtitle: "Books, courses, concepts, and knowledge you're building",
    ),
  ];

  void _toggleOption(String id) {
    setState(() {
      if (_selectedOptionIds.contains(id)) {
        _selectedOptionIds.remove(id);
      } else {
        _selectedOptionIds.add(id);
      }
    });
  }

  Future<void> _onContinuePressed() async {
    if (_selectedOptionIds.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('personalization_use_cases', _selectedOptionIds.toList());
    await prefs.setBool('has_seen_onboarding', true);

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthSessionGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedOptionIds.isNotEmpty;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Circular Back Arrow Button
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundColor,
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: textPrimaryColor,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Heading: 19-20px, Bold, #1A1A1A
              const Text(
                'How will you use your second brain?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: textPrimaryColor,
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle: 13px, Regular, #8A8A8A
              const Text(
                "We'll personalise your experience to fit.",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: textSecondaryColor,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 32),

              // Selection Cards List
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final option = _options[index];
                    final isSelected = _selectedOptionIds.contains(option.id);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? primaryColor : inactiveBorderColor,
                          width: isSelected ? 1.6 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(
                              alpha: isSelected ? 0.12 : 0.04,
                            ),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _toggleOption(option.id),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18.0,
                              vertical: 18.0,
                            ),
                            child: Row(
                              children: [
                                // Circular Icon Container
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    color: lightCyanTint,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    option.icon,
                                    color: primaryColor,
                                    size: 24,
                                  ),
                                ),

                                const SizedBox(width: 16),

                                // Title and Subtitle
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.title,
                                        style: const TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        option.subtitle,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                          color: textSecondaryColor,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 12),

                                // Radio/Checkbox Circle
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? primaryColor : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected
                                          ? primaryColor
                                          : indicatorBorderColor,
                                      width: 1.8,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Action Button
              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: hasSelection ? primaryGradient : null,
                  color: hasSelection ? null : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: hasSelection ? _onContinuePressed : null,
                    borderRadius: BorderRadius.circular(100),
                    child: Center(
                      child: Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hasSelection
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
