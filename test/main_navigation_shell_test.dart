import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/core/theme/app_colors.dart';
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
import 'package:second_brain/features/capture/presentation/bloc/capture_state.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_detail_screen.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';
import 'package:second_brain/features/navigation/presentation/screens/main_navigation_shell.dart';
import 'package:second_brain/features/saved/presentation/screens/saved_screen.dart';
import 'package:second_brain/features/search/presentation/screens/search_screen.dart';
import 'package:second_brain/features/settings/presentation/screens/settings_screen.dart';
import 'package:second_brain/main.dart';

class FakeAuthRepository implements AuthRepository {
  UserEntity? currentUser;
  final StreamController<UserEntity?> _authController =
      StreamController<UserEntity?>.broadcast();

  FakeAuthRepository({this.currentUser});

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

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository([List<MemoryEntity>? initial])
      : memories = initial ?? [];

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async =>
      List<MemoryEntity>.from(memories);

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    final idx = memories.indexWhere((m) => m.id == memory.id);
    if (idx >= 0) {
      memories[idx] = memory;
    } else {
      memories.add(memory);
    }
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

class FakeLoadedCaptureBloc extends CaptureBloc {
  final CaptureState _stubbedState;

  FakeLoadedCaptureBloc(
    CaptureRepository repo,
    this._stubbedState,
  ) : super(
          saveMemoryUseCase: SaveMemoryUseCase(repo),
          getMemoriesUseCase: GetMemoriesUseCase(repo),
          repository: repo,
        );

  @override
  CaptureState get state => _stubbedState;

  @override
  Stream<CaptureState> get stream => const Stream.empty();
}

void main() {
  late FakeAuthRepository fakeAuthRepository;
  late FakeCaptureRepository fakeCaptureRepository;
  late AuthBloc authBloc;
  late CaptureBloc captureBloc;

  final testPinnedMemory = MemoryEntity(
    id: 'pinned-mem-1',
    userId: 'u-1',
    title: 'Important Pinned Note',
    content: 'Secrets of building resilient Flutter architectures.',
    category: 'Work',
    tags: const ['pinned', 'architecture'],
    clientCreatedAt: DateTime(2026, 9, 15, 10, 0),
    clientUpdatedAt: DateTime(2026, 9, 15, 10, 0),
    serverUpdatedAt: DateTime(2026, 9, 15, 10, 0),
  );

  final testUnpinnedMemory = MemoryEntity(
    id: 'regular-mem-2',
    userId: 'u-1',
    title: 'Regular Grocery List',
    content: 'Milk, bread, eggs, cheese.',
    category: 'Personal',
    tags: const ['shopping'],
    clientCreatedAt: DateTime(2026, 9, 14, 10, 0),
    clientUpdatedAt: DateTime(2026, 9, 14, 10, 0),
    serverUpdatedAt: DateTime(2026, 9, 14, 10, 0),
  );

  setUp(() {
    fakeAuthRepository = FakeAuthRepository(
      currentUser: const UserEntity(
        id: 'u-1',
        email: 'tester@secondbrain.app',
        fullName: 'Alex Mercer',
      ),
    );

    fakeCaptureRepository = FakeCaptureRepository([
      testPinnedMemory,
      testUnpinnedMemory,
    ]);

    authBloc = AuthBloc(
      signUpUseCase: SignUpUseCase(fakeAuthRepository),
      signInUseCase: SignInUseCase(fakeAuthRepository),
      signOutUseCase: SignOutUseCase(fakeAuthRepository),
      getCurrentUserUseCase: GetCurrentUserUseCase(fakeAuthRepository),
      authRepository: fakeAuthRepository,
    )..add(AuthCheckRequested());

    captureBloc = CaptureBloc(
      saveMemoryUseCase: SaveMemoryUseCase(fakeCaptureRepository),
      getMemoriesUseCase: GetMemoriesUseCase(fakeCaptureRepository),
      subscribeToMemoriesUseCase:
          SubscribeToMemoriesUseCase(fakeCaptureRepository),
      repository: fakeCaptureRepository,
    )..add(LoadMemoriesEvent());
  });

  tearDown(() {
    authBloc.close();
    captureBloc.close();
    fakeAuthRepository.dispose();
  });

  Widget buildApp({Widget? home}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: authBloc),
        BlocProvider<CaptureBloc>.value(value: captureBloc),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
        ),
        home: home ?? const MainNavigationShell(userName: 'Alex Mercer'),
      ),
    );
  }

  group('MainNavigationShell — Structure & Tab Switching Tests', () {
    testWidgets('renders all 5 bottom navigation destinations: Home, Search, +, Saved, Settings',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.byKey(const Key('bottom_nav_add_btn')), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('starts on Home tab displaying HomeScreen and greeting',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Hello Alex Mercer'), findsOneWidget);
    });

    testWidgets('tapping Search tab switches to existing SearchScreen',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('tapping center + button opens existing capture options sheet with 6 options',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
      await tester.pumpAndSettle();

      expect(find.text('What do you want to save?'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Scan Document'), findsOneWidget);
      expect(find.text('Add Link'), findsOneWidget);
      expect(find.text('Add Note'), findsOneWidget);
      expect(find.text('Record Voice'), findsOneWidget);
      expect(find.text('Choose File'), findsOneWidget);
    });

    testWidgets('tapping Saved tab switches to SavedScreen with pinned memories',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();

      expect(find.byType(SavedScreen), findsOneWidget);
      expect(find.text('Important Pinned Note'), findsOneWidget);
      // Unpinned memory must NOT appear in Saved
      expect(find.text('Regular Grocery List'), findsNothing);
    });

    testWidgets('tapping Settings tab switches to SettingsScreen with sections',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('Alex Mercer'), findsOneWidget);
      expect(find.text('tester@secondbrain.app'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('DATA & STORAGE'), 200);
      expect(find.text('DATA & STORAGE'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('ABOUT'), 200);
      expect(find.text('ABOUT'), findsOneWidget);
    });
  });

  group('MainNavigationShell — Single Capture Entry Point Tests', () {
    testWidgets('Home tab does not display floating ActionButton (+)',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Verified: FloatingActionButton is removed from Home screen
      expect(find.byType(FloatingActionButton), findsNothing);
      // Center + bottom nav button is present
      expect(find.byKey(const Key('bottom_nav_add_btn')), findsOneWidget);
    });

    testWidgets('all tabs have no FloatingActionButton and use center + as single capture point',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);

      // Switch to Search tab
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      // Switch to Saved tab
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      // Switch to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      // Center + bottom navigation remains the single capture entry point
      expect(find.byKey(const Key('bottom_nav_add_btn')), findsOneWidget);
    });
  });

  group('MainNavigationShell — Home Header Shortcuts & Tab Transition Tests', () {
    testWidgets('tapping search bar on Home switches to Search tab without duplicate shell',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Tap search bar in home header
      await tester.tap(find.text(AppStrings.homeSearchHint));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
      // Navigation shell must NOT be duplicated
      expect(find.byType(MainNavigationShell), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });

    testWidgets('tapping center + button from Search tab opens capture sheet and preserves active tab',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Switch to Search tab
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      // Tap center + button
      await tester.tap(find.byKey(const Key('bottom_nav_add_btn')));
      await tester.pumpAndSettle();

      expect(find.text('What do you want to save?'), findsOneWidget);

      // Dismiss bottom sheet
      Navigator.of(tester.element(find.text('What do you want to save?'))).pop();
      await tester.pumpAndSettle();

      // Verified: Remains on Search tab
      expect(find.byType(SearchScreen), findsOneWidget);
    });
  });

  group('SavedScreen — State, Navigation & Empty View Tests', () {
    testWidgets('SavedScreen renders empty state when no memories are pinned',
        (tester) async {
      final emptyCaptureBloc = FakeLoadedCaptureBloc(
        fakeCaptureRepository,
        const CaptureLoaded([]),
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authBloc),
            BlocProvider<CaptureBloc>.value(value: emptyCaptureBloc),
          ],
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: AppColors.background,
            ),
            home: const MainNavigationShell(
              userName: 'Alex Mercer',
              initialIndex: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No saved memories yet'), findsOneWidget);
      expect(
        find.text(
            'Pinned memories will appear here. Pin important notes, links, or ideas from your Home screen to access them quickly.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping saved memory opens MemoryDetailScreen with exact id',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();

      expect(find.text('Important Pinned Note'), findsOneWidget);

      await tester.tap(find.text('Important Pinned Note'));
      await tester.pumpAndSettle();

      final detailFinder = find.byType(MemoryDetailScreen);
      expect(detailFinder, findsOneWidget);
      final detailScreen = tester.widget<MemoryDetailScreen>(detailFinder);
      expect(detailScreen.memoryId, 'pinned-mem-1');
    });
  });

  group('SettingsScreen — Sign Out & Storage Interaction Tests', () {
    testWidgets('tapping Sign Out opens confirmation dialog and dispatches SignOutRequested',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      expect(
        find.text('Are you sure you want to sign out of Second Brain?'),
        findsOneWidget,
      );

      // Confirm sign out in dialog
      await tester.tap(find.widgetWithText(TextButton, 'Sign Out'));
      await tester.pumpAndSettle();

      expect(fakeAuthRepository.currentUser, isNull);
    });

    testWidgets('tapping Sync Offline Memories triggers sync and shows snackbar',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Sync Offline Memories'), 200);
      await tester.tap(find.text('Sync Offline Memories'));
      await tester.pump();

      expect(find.text('Syncing memories with cloud...'), findsOneWidget);
    });
  });

  group('AuthSessionGate Integration Tests', () {
    testWidgets('AuthSessionGate renders MainNavigationShell when authenticated',
        (tester) async {
      await tester.pumpWidget(buildApp(home: const AuthSessionGate()));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationShell), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });
  });
}
