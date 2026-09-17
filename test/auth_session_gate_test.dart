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
import 'package:second_brain/features/auth/presentation/bloc/auth_state.dart';
import 'package:second_brain/features/auth/presentation/screens/auth_screen.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';
import 'package:second_brain/main.dart';

class FakeAuthRepository implements AuthRepository {
  UserEntity? currentUser;
  Completer<UserEntity>? pendingSignInCompleter;
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
    if (pendingSignInCompleter != null) {
      final user = await pendingSignInCompleter!.future;
      currentUser = user;
      _authController.add(currentUser);
      return user;
    }
    currentUser = UserEntity(id: 'user-123', email: email);
    _authController.add(currentUser);
    return currentUser!;
  }

  @override
  Future<UserEntity> signUp(
      {required String email,
      required String password,
      String? fullName}) async {
    currentUser =
        UserEntity(id: 'user-123', email: email, fullName: fullName);
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
  int getMemoriesCallCount = 0;

  FakeCaptureRepository([List<MemoryEntity>? initial])
      : memories = initial ?? [];

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async {
    getMemoriesCallCount++;
    return memories;
  }

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    memories.add(memory);
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository fakeAuthRepository;
  late FakeCaptureRepository fakeCaptureRepository;
  late CaptureBloc captureBloc;

  setUp(() {
    fakeAuthRepository = FakeAuthRepository();
    fakeCaptureRepository = FakeCaptureRepository();
    captureBloc = CaptureBloc(
      saveMemoryUseCase: SaveMemoryUseCase(fakeCaptureRepository),
      getMemoriesUseCase: GetMemoriesUseCase(fakeCaptureRepository),
      repository: fakeCaptureRepository,
    );
  });

  tearDown(() {
    fakeAuthRepository.dispose();
    captureBloc.close();
  });

  Widget buildTestWidget({
    required AuthBloc authBloc,
  }) {
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
        home: const AuthSessionGate(),
      ),
    );
  }

  group('AuthSessionGate State Rendering Tests', () {
    testWidgets('renders CircularProgressIndicator when state is AuthLoading',
        (tester) async {
      final completer = Completer<UserEntity>();
      fakeAuthRepository.pendingSignInCompleter = completer;

      final authBloc = AuthBloc(
        signUpUseCase: SignUpUseCase(fakeAuthRepository),
        signInUseCase: SignInUseCase(fakeAuthRepository),
        signOutUseCase: SignOutUseCase(fakeAuthRepository),
        getCurrentUserUseCase: GetCurrentUserUseCase(fakeAuthRepository),
        authRepository: fakeAuthRepository,
      );

      // Trigger sign in which puts AuthBloc into AuthLoading state while awaiting repository
      authBloc.add(
        const SignInRequested(
          email: 'loading@example.com',
          password: 'password123',
        ),
      );

      await tester.pumpWidget(buildTestWidget(authBloc: authBloc));
      await tester.pump();

      expect(authBloc.state, isA<AuthLoading>());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AuthScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);

      completer.complete(
        const UserEntity(id: 'user-123', email: 'loading@example.com'),
      );
      await tester.pump();
      await tester.pump();

      await tester.runAsync(authBloc.close);
    });

    testWidgets('renders AuthScreen when user is unauthenticated',
        (tester) async {
      fakeAuthRepository.currentUser = null;
      final authBloc = AuthBloc(
        signUpUseCase: SignUpUseCase(fakeAuthRepository),
        signInUseCase: SignInUseCase(fakeAuthRepository),
        signOutUseCase: SignOutUseCase(fakeAuthRepository),
        getCurrentUserUseCase: GetCurrentUserUseCase(fakeAuthRepository),
        authRepository: fakeAuthRepository,
      );

      // Trigger check
      authBloc.add(AuthCheckRequested());

      await tester.pumpWidget(buildTestWidget(authBloc: authBloc));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.text(AppStrings.authWelcomeTitle), findsOneWidget);
      expect(find.text(AppStrings.signInButton), findsWidgets);
      expect(find.byType(HomeScreen), findsNothing);

      await tester.runAsync(authBloc.close);
    });

    testWidgets('renders HomeScreen and loads memories when user is authenticated',
        (tester) async {
      fakeAuthRepository.currentUser = const UserEntity(
        id: 'user-saved-session',
        email: 'user@example.com',
        fullName: 'Jane Doe',
      );

      final authBloc = AuthBloc(
        signUpUseCase: SignUpUseCase(fakeAuthRepository),
        signInUseCase: SignInUseCase(fakeAuthRepository),
        signOutUseCase: SignOutUseCase(fakeAuthRepository),
        getCurrentUserUseCase: GetCurrentUserUseCase(fakeAuthRepository),
        authRepository: fakeAuthRepository,
      );

      // Dispatch check
      authBloc.add(AuthCheckRequested());

      await tester.pumpWidget(buildTestWidget(authBloc: authBloc));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AuthScreen), findsNothing);
      expect(fakeCaptureRepository.getMemoriesCallCount, greaterThanOrEqualTo(1));

      await tester.runAsync(authBloc.close);
    });

    testWidgets(
        'transitions from AuthScreen to HomeScreen upon successful sign in',
        (tester) async {
      fakeAuthRepository.currentUser = null;

      final authBloc = AuthBloc(
        signUpUseCase: SignUpUseCase(fakeAuthRepository),
        signInUseCase: SignInUseCase(fakeAuthRepository),
        signOutUseCase: SignOutUseCase(fakeAuthRepository),
        getCurrentUserUseCase: GetCurrentUserUseCase(fakeAuthRepository),
        authRepository: fakeAuthRepository,
      );

      authBloc.add(AuthCheckRequested());

      await tester.pumpWidget(buildTestWidget(authBloc: authBloc));
      await tester.pumpAndSettle();

      // Verify on AuthScreen initially
      expect(find.byType(AuthScreen), findsOneWidget);

      // Trigger sign in
      authBloc.add(
        const SignInRequested(
          email: 'valid@example.com',
          password: 'password123',
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Gate has transitioned to HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(fakeCaptureRepository.getMemoriesCallCount, greaterThanOrEqualTo(1));

      await tester.runAsync(authBloc.close);
    });

    testWidgets(
        'transitions from AuthScreen to HomeScreen upon successful sign up',
        (tester) async {
      fakeAuthRepository.currentUser = null;

      final authBloc = AuthBloc(
        signUpUseCase: SignUpUseCase(fakeAuthRepository),
        signInUseCase: SignInUseCase(fakeAuthRepository),
        signOutUseCase: SignOutUseCase(fakeAuthRepository),
        getCurrentUserUseCase: GetCurrentUserUseCase(fakeAuthRepository),
        authRepository: fakeAuthRepository,
      );

      authBloc.add(AuthCheckRequested());

      await tester.pumpWidget(buildTestWidget(authBloc: authBloc));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);

      // Trigger sign up
      authBloc.add(
        const SignUpRequested(
          email: 'newuser@example.com',
          password: 'password123',
          fullName: 'New User',
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Gate has transitioned to HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.runAsync(authBloc.close);
    });
  });
}
