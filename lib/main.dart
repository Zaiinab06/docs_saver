import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'core/constants/supabase_constants.dart';
import 'core/services/isar_service.dart';
import 'core/theme/app_colors.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/domain/usecases/get_current_user_usecase.dart';
import 'features/auth/domain/usecases/sign_in_usecase.dart';
import 'features/auth/domain/usecases/sign_out_usecase.dart';
import 'features/auth/domain/usecases/sign_up_usecase.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';
import 'features/capture/data/datasources/capture_local_data_source.dart';
import 'features/capture/data/datasources/capture_remote_data_source.dart';
import 'features/capture/domain/repositories/capture_repository_impl.dart';
import 'features/capture/domain/usecases/get_memories_usecase.dart';
import 'features/capture/domain/usecases/save_memory_usecase.dart';
import 'features/capture/domain/usecases/subscribe_to_memories_usecase.dart';
import 'features/capture/presentation/bloc/capture_bloc.dart';
import 'features/capture/presentation/bloc/capture_event.dart';
import 'features/home/presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    publishableKey: SupabaseConstants.supabaseAnonKey,
  );

  await IsarService.init();

  // Reset/override has_seen_onboarding flag to ensure OnboardingScreen renders on launch
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('has_seen_onboarding', false);

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
  final subscribeToMemoriesUseCase =
      SubscribeToMemoriesUseCase(captureRepository);

  runApp(
    SecondBrainApp(
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
}

class SecondBrainApp extends StatelessWidget {
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
      child: MaterialApp(
        title: '2nd Brain',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            surface: AppColors.cardBackground,
          ),
        ),
        // Temporary Development Bypass: Land directly on HomeScreen
        home: const HomeScreen(),
      ),
    );
  }
}

class AuthSessionGate extends StatelessWidget {
  const AuthSessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Temporary Development Bypass: Direct to HomeScreen
    return const HomeScreen();
  }
}
