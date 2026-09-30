import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/utils/profile_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'core/constants/supabase_constants.dart';
import 'core/network/network_checker.dart';
import 'core/services/isar_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/domain/usecases/get_current_user_usecase.dart';
import 'features/auth/domain/usecases/sign_in_usecase.dart';
import 'features/auth/domain/usecases/sign_out_usecase.dart';
import 'features/auth/domain/usecases/sign_up_usecase.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'features/capture/data/datasources/capture_local_data_source.dart';
import 'features/capture/data/datasources/capture_remote_data_source.dart';
import 'features/capture/domain/repositories/capture_repository_impl.dart';
import 'features/capture/domain/usecases/get_memories_usecase.dart';
import 'features/capture/domain/usecases/save_memory_usecase.dart';
import 'features/capture/domain/usecases/subscribe_to_memories_usecase.dart';
import 'features/capture/presentation/bloc/capture_bloc.dart';
import 'features/capture/presentation/bloc/capture_event.dart';
import 'features/navigation/presentation/screens/main_navigation_shell.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    publishableKey: SupabaseConstants.supabaseAnonKey,
  );

  await IsarService.init();

  NetworkChecker.startMonitoring();

  await ProfileNotifier.loadProfile();

  final prefs = await SharedPreferences.getInstance();

  // Auth feature dependencies
  final authRemoteDataSource = AuthRemoteDataSourceImpl();
  final authRepository = AuthRepositoryImpl(
    remoteDataSource: authRemoteDataSource,
  );
  final signUpUseCase = SignUpUseCase(authRepository);
  final signInUseCase = SignInUseCase(authRepository);
  final signOutUseCase = SignOutUseCase(authRepository);
  final getCurrentUserUseCase = GetCurrentUserUseCase(authRepository);

  // Capture feature dependencies
  final localDataSource = CaptureLocalDataSourceImpl();
  final remoteDataSource = CaptureRemoteDataSourceImpl();
  final captureRepository = CaptureRepositoryImpl(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
  );
  final saveMemoryUseCase = SaveMemoryUseCase(captureRepository);
  final getMemoriesUseCase = GetMemoriesUseCase(captureRepository);
  final subscribeToMemoriesUseCase = SubscribeToMemoriesUseCase(
    captureRepository,
  );

  final themeCubit = ThemeCubit(prefs);

  runApp(
    SecondBrainApp(prefs: prefs,
      themeCubit: themeCubit,
      authRepository: authRepository,
      signUpUseCase: signUpUseCase,
      signInUseCase: signInUseCase,
      signOutUseCase: signOutUseCase,
      getCurrentUserUseCase: getCurrentUserUseCase,
      captureRepository: captureRepository,
      saveMemoryUseCase: saveMemoryUseCase,
      getMemoriesUseCase: getMemoriesUseCase,
      subscribeToMemoriesUseCase: subscribeToMemoriesUseCase,
    ),
  );
    FlutterNativeSplash.remove();
  }

class SecondBrainApp extends StatelessWidget {
  final ThemeCubit? themeCubit;
  final SharedPreferences prefs;
  final AuthRepository authRepository;
  final SignUpUseCase signUpUseCase;
  final SignInUseCase signInUseCase;
  final SignOutUseCase signOutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  final CaptureRepositoryImpl captureRepository;
  final SaveMemoryUseCase saveMemoryUseCase;
  final GetMemoriesUseCase getMemoriesUseCase;
  final SubscribeToMemoriesUseCase subscribeToMemoriesUseCase;

  const SecondBrainApp({
    super.key,
    this.themeCubit,
    required this.prefs,
    required this.authRepository,
    required this.signUpUseCase,
    required this.signInUseCase,
    required this.signOutUseCase,
    required this.getCurrentUserUseCase,
    required this.captureRepository,
    required this.saveMemoryUseCase,
    required this.getMemoriesUseCase,
    required this.subscribeToMemoriesUseCase,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: themeCubit ?? ThemeCubit()),
        BlocProvider(
          create: (context) => AuthBloc(
            signUpUseCase: signUpUseCase,
            signInUseCase: signInUseCase,
            signOutUseCase: signOutUseCase,
            getCurrentUserUseCase: getCurrentUserUseCase,
            authRepository: authRepository,
          )..add(AuthCheckRequested()),
        ),
        BlocProvider(
          create: (context) => CaptureBloc(
            saveMemoryUseCase: saveMemoryUseCase,
            getMemoriesUseCase: getMemoriesUseCase,
            subscribeToMemoriesUseCase: subscribeToMemoriesUseCase,
            repository: captureRepository,
          )..add(LoadMemoriesEvent()),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: '2nd Brain',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: AuthSessionGate(prefs: prefs),
          );
        },
      ),
    );
  }
}

class AuthSessionGate extends StatefulWidget {
  final SharedPreferences prefs;

  const AuthSessionGate({super.key, required this.prefs});

  @override
  State<AuthSessionGate> createState() => _AuthSessionGateState();
}

class _AuthSessionGateState extends State<AuthSessionGate> {
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          context.read<CaptureBloc>().add(ClearMemoriesEvent());
        }
        if (state is Authenticated ||
            (state is AuthSuccess && state.user.hasSession)) {
          context.read<CaptureBloc>().add(LoadMemoriesEvent());
        }
      },
      builder: (context, state) {
        if (state is Authenticated ||
            (state is AuthSuccess && state.user.hasSession)) {
          final user = state is Authenticated
              ? state.user
              : (state as AuthSuccess).user;
          return MainNavigationShell(userName: user.fullName);
        } else if (state is AuthLoading || state is AuthInitial) {
          return Scaffold(
            backgroundColor: const Color(0xFF134E3F),
            body: Center(
              child: Image.asset(
                'assets/app_icon.png',
                width: 120,
                height: 120,
              ),
            ),
          );
        } else {
          final hasSeen = widget.prefs.getBool('has_seen_onboarding') ?? false;
          if (!hasSeen) {
            return const OnboardingScreen();
          }
          return const AuthScreen();
        }
      },
    );
  }
}

