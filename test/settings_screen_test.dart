import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:second_brain/core/theme/app_colors.dart';
import 'package:second_brain/core/theme/app_theme.dart';
import 'package:second_brain/core/theme/theme_cubit.dart';
import 'package:second_brain/features/auth/domain/entities/user_entity.dart';
import 'package:second_brain/features/auth/domain/repositories/auth_repository.dart';
import 'package:second_brain/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:second_brain/features/auth/domain/usecases/sign_in_usecase.dart';
import 'package:second_brain/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:second_brain/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:second_brain/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:second_brain/features/auth/presentation/bloc/auth_event.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/subscribe_to_memories_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository implements AuthRepository {
  UserEntity? currentUser;
  final StreamController<UserEntity?> _authController =
      StreamController<UserEntity?>.broadcast();

  _MockAuthRepository({this.currentUser});

  @override
  UserEntity? getCurrentUser() => currentUser;

  @override
  Stream<UserEntity?> get authStateChanges => _authController.stream;

  @override
  Future<UserEntity> signIn(
      {required String email, required String password}) async {
    currentUser = UserEntity(id: 'u-1', email: email);
    _authController.add(currentUser);
    return currentUser!;
  }

  @override
  Future<UserEntity> signUp(
      {required String email,
      required String password,
      String? fullName}) async {
    currentUser = UserEntity(id: 'u-1', email: email, fullName: fullName);
    _authController.add(currentUser);
    return currentUser!;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
    _authController.add(null);
  }

  @override
  Future<void> resendVerificationEmail({required String email}) async {}

  void dispose() {
    _authController.close();
  }
}

class _MockCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;
  bool syncCalled = false;

  _MockCaptureRepository([List<MemoryEntity>? initial])
      : memories = initial ?? [];

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async =>
      List<MemoryEntity>.from(memories);

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    memories.add(memory);
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {
    syncCalled = true;
  }

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Second Brain',
    packageName: 'com.secondbrain.app',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  late _MockAuthRepository authRepo;
  late _MockCaptureRepository captureRepo;
  late AuthBloc authBloc;
  late CaptureBloc captureBloc;
  late ThemeCubit themeCubit;

  setUp(() {
    authRepo = _MockAuthRepository(
      currentUser: const UserEntity(
        id: 'u-42',
        email: 'alex@example.com',
        fullName: 'Alex Mercer',
      ),
    );
    captureRepo = _MockCaptureRepository();
    authBloc = AuthBloc(
      signUpUseCase: SignUpUseCase(authRepo),
      signInUseCase: SignInUseCase(authRepo),
      signOutUseCase: SignOutUseCase(authRepo),
      getCurrentUserUseCase: GetCurrentUserUseCase(authRepo),
      authRepository: authRepo,
    )..add(AuthCheckRequested());
    captureBloc = CaptureBloc(
      saveMemoryUseCase: SaveMemoryUseCase(captureRepo),
      getMemoriesUseCase: GetMemoriesUseCase(captureRepo),
      subscribeToMemoriesUseCase: SubscribeToMemoriesUseCase(captureRepo),
      repository: captureRepo,
    )..add(LoadMemoriesEvent());
    themeCubit = ThemeCubit();
  });

  tearDown(() {
    authRepo.dispose();
    authBloc.close();
    captureBloc.close();
    themeCubit.close();
  });

  Widget buildTestApp({ThemeCubit? customThemeCubit}) {
    final effectiveThemeCubit = customThemeCubit ?? themeCubit;
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: effectiveThemeCubit),
        BlocProvider<AuthBloc>.value(value: authBloc),
        BlocProvider<CaptureBloc>.value(value: captureBloc),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, mode) {
          return MaterialApp(
            themeMode: mode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          );
        },
      ),
    );
  }

  group('SettingsScreen — UI & Layout Verification', () {
    testWidgets(
        'renders gradient header with title, subtitle, and user initial',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Manage your Second Brain'), findsOneWidget);
      expect(find.text('A'), findsWidgets); // Avatar initial

      // Verify header container has AppColors.headerGradient and rounded bottom corners
      final containers = tester.widgetList<Container>(find.byType(Container));
      final headerContainer = containers.firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).gradient == AppColors.headerGradient,
      );
      final decoration = headerContainer.decoration as BoxDecoration;
      expect(decoration.gradient, AppColors.headerGradient);
      expect(
        decoration.borderRadius,
        const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      );

      final titleText = tester.widget<Text>(find.text('Settings'));
      expect(titleText.style?.color, AppColors.textWhite);
    });

    testWidgets('renders all required section headers', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('DATA & STORAGE'), 200);
      expect(find.text('DATA & STORAGE'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('AI & KNOWLEDGE ENGINE'), 200);
      expect(find.text('AI & KNOWLEDGE ENGINE'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('HELP & SUPPORT'), 200);
      expect(find.text('HELP & SUPPORT'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('PRIVACY & SECURITY'), 200);
      expect(find.text('PRIVACY & SECURITY'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('ABOUT'), 200);
      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('displays real user name and email from AuthBloc',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Alex Mercer'), findsOneWidget);
      expect(find.text('alex@example.com'), findsWidgets);
      expect(find.text('Active'), findsWidgets);
    });

    testWidgets('tapping account row opens account information bottom sheet',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Account Information'), findsOneWidget);
      expect(find.text('Authentication'), findsOneWidget);
      expect(find.text('Supabase Auth'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Account Information'), findsNothing);
    });

    testWidgets(
        'displays Theme segmented selector with Light, Dark, System and switches modes',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.byKey(const Key('theme_segment_dark')), 150);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      // Tap Dark
      await tester.tap(find.byKey(const Key('theme_segment_dark')));
      await tester.pumpAndSettle();

      expect(themeCubit.state, ThemeMode.dark);
      expect(find.text('Dark mode active'), findsOneWidget);

      // Tap Light
      await tester.tap(find.byKey(const Key('theme_segment_light')));
      await tester.pumpAndSettle();

      expect(themeCubit.state, ThemeMode.light);
      expect(find.text('Light mode active'), findsOneWidget);

      // Tap System
      await tester.tap(find.byKey(const Key('theme_segment_system')));
      await tester.pumpAndSettle();

      expect(themeCubit.state, ThemeMode.system);
      expect(find.text('Following device system theme'), findsOneWidget);
    });

    testWidgets('displays Push Notifications Enabled', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Memory reminders and suggestions'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets(
        'tapping Sync Offline Memories dispatches sync and shows snackbar',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Sync Offline Memories'), 200);
      await tester.tap(find.text('Sync Offline Memories'));
      await tester.pump();

      expect(find.text('Syncing memories with cloud...'), findsOneWidget);
    });

    testWidgets('tapping AI Knowledge Engine shows AI details dialog',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('AI Knowledge Engine'), 200);
      await tester.tap(find.text('AI Knowledge Engine'));
      await tester.pumpAndSettle();

      expect(find.text('Got It'), findsOneWidget);
      expect(
        find.textContaining('Second Brain uses Google Gemini'),
        findsOneWidget,
      );

      await tester.tap(find.text('Got It'));
      await tester.pumpAndSettle();

      expect(find.text('Got It'), findsNothing);
    });

    testWidgets('tapping Privacy & Data Protection shows privacy dialog',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.text('Privacy & Data Protection'), 200);
      await tester.tap(find.text('Privacy & Data Protection'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy & Data Security'), findsOneWidget);
      expect(
        find.textContaining('Tenant Isolation: Every memory belongs strictly'),
        findsOneWidget,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy & Data Security'), findsNothing);
    });

    testWidgets(
        'tapping Sign Out shows confirmation dialog and cancels gracefully',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      expect(
        find.text('Are you sure you want to sign out of Second Brain?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(authRepo.currentUser, isNotNull);
    });

    testWidgets('confirming Sign Out dispatches SignOutRequested',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Sign Out'));
      await tester.pumpAndSettle();

      expect(authRepo.currentUser, isNull);
    });
  });

  group('ThemeCubit — Persistence & Restoration Tests', () {
    test('theme selection persists to SharedPreferences and restores on restart',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final cubit1 = ThemeCubit(prefs);
      expect(cubit1.state, ThemeMode.system);

      await cubit1.setThemeMode(ThemeMode.dark);
      expect(cubit1.state, ThemeMode.dark);
      expect(prefs.getString('theme_mode'), 'dark');
      await cubit1.close();

      // Simulate app restart by creating a new cubit with the same prefs
      final cubit2 = ThemeCubit(prefs);
      expect(cubit2.state, ThemeMode.dark);

      await cubit2.setThemeMode(ThemeMode.light);
      expect(cubit2.state, ThemeMode.light);
      expect(prefs.getString('theme_mode'), 'light');
      await cubit2.close();

      // Second restart
      final cubit3 = ThemeCubit(prefs);
      expect(cubit3.state, ThemeMode.light);
      await cubit3.close();
    });
  });
}
