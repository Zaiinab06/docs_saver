import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../saved/presentation/screens/saved_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';

class MainNavigationShell extends StatefulWidget {
  final String? userName;
  final int initialIndex;

  const MainNavigationShell({super.key, this.userName, this.initialIndex = 0});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex == 2 ? 0 : widget.initialIndex;
  }

  void _onTabSelected(int index) {
    if (index == 2) {
      _showCaptureBottomSheet();
      return;
    }
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
  }

  void _showCaptureBottomSheet() {
    _homeKey.currentState?.openCaptureBottomSheet();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;
    final navBg = isDark
        ? AppColors.darkCardBackground
        : AppColors.cardBackground;
    final navBorder = isDark
        ? AppColors.darkSubtleBorder
        : AppColors.chipInactiveBorder;
    final selectedNavColor = isDark
        ? AppColors.periwinkle300
        : AppColors.primary;
    final unselectedNavColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        resizeToAvoidBottomInset: false,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              key: _homeKey,
              userName: widget.userName,
              onSearchTap: () => setState(() => _currentIndex = 1),
              onSavedTap: () => setState(() => _currentIndex = 3),
            ),
            SearchScreen(
              isActive: _currentIndex == 1,
              showBackButton: false,
              autofocus: false,
            ),
            const SizedBox.shrink(),
            const SavedScreen(),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: navBg,
                  border: Border(top: BorderSide(color: navBorder, width: 1.0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: _onTabSelected,
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: selectedNavColor,
                  unselectedItemColor: unselectedNavColor,
                  selectedFontSize: 11.5,
                  unselectedFontSize: 11.5,
                  selectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                  items: [
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined),
                      activeIcon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.search_rounded),
                      activeIcon: Icon(Icons.search_rounded),
                      label: 'Search',
                    ),
                    BottomNavigationBarItem(
                      icon: Container(
                        key: const Key('bottom_nav_add_btn'),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.38),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              color: AppColors.textWhite,
                              size: 28,
                            ),
                            Opacity(
                              opacity: 0.0,
                              child: Text(
                                '+',
                                style: TextStyle(
                                  fontSize: 1,
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      activeIcon: Container(
                        key: const Key('bottom_nav_add_btn_active'),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.38),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              color: AppColors.textWhite,
                              size: 28,
                            ),
                            Opacity(
                              opacity: 0.0,
                              child: Text(
                                '+',
                                style: TextStyle(
                                  fontSize: 1,
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      label: '',
                      tooltip: 'Capture',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.bookmark_border_rounded),
                      activeIcon: Icon(Icons.bookmark_rounded),
                      label: 'Saved',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.settings_outlined),
                      activeIcon: Icon(Icons.settings_rounded),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
