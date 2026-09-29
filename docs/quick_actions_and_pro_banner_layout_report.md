# Quick Actions & Pro Banner Layout Update Report

## Overview
This report details the styling and layout enhancements applied to [lib/features/home/presentation/screens/home_screen.dart](lib/features/home/presentation/screens/home_screen.dart).

## Changes Made

### 1. Quick Action Colors
Updated color schemes for specific quick actions in both `_buildQuickActions` and `_showCaptureSheet` modal sheet:
- **'Choose File'**:
  - Container Background: `Color(0xFFE8EEF8)` (Soft Blue)
  - Icon Color: `Color(0xFF2B5EA7)` (Deep Blue)
- **'Take Photo' (Camera)**:
  - Container Background: `Color(0xFFFFF2DC)` (Soft Amber)
  - Icon Color: `Color(0xFFD97706)` (Warm Amber)
- **'Add Link'**:
  - Kept as current Pale Sage Green (`Color(0xFFE5EFE9)` background and `Color(0xFF1E5E48)` icon color).

### 2. 'Go Pro' Button Layout
Fixed the layout of the 'Go Pro' button inside `_buildProUpgradeBanner`:
- Wrapped with `Align(alignment: Alignment.center, child: SizedBox(height: 36, ...))` to ensure vertical centering on the right side next to the text column without distortion.
- Assigned a fixed vertical height of `36`.
- Applied compact padding: `EdgeInsets.symmetric(horizontal: 14, vertical: 6)`.
- Centered content (`Row` with `MainAxisSize.min` and `MainAxisAlignment.center`) to prevent stretching.
- Maintained all interaction logic (`_showUnavailableFeature('DocsSaver Pro')`).

## Verification
- Code formatted using `dart_format`.
- Static analysis via `flutter analyze`: **No issues found! (0 errors)**.
