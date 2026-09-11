import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/capture/domain/repositories/capture_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'core/services/isar_service.dart';
import 'features/capture/data/datasources/capture_local_data_source.dart';
import 'features/capture/data/datasources/capture_remote_data_source.dart';
import 'features/capture/domain/usecases/get_memories_usecase.dart';
import 'features/capture/domain/usecases/save_memory_usecase.dart';
import 'features/capture/presentation/bloc/capture_bloc.dart';
import 'features/capture/presentation/bloc/capture_event.dart';
import 'features/capture/presentation/screens/capture_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    publishableKey: SupabaseConstants.supabaseAnonKey,
  );

  await IsarService.init();

  final localDataSource = CaptureLocalDataSourceImpl();
  final remoteDataSource = CaptureRemoteDataSourceImpl();
  final captureRepository = CaptureRepositoryImpl(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
  );
  final saveMemoryUseCase = SaveMemoryUseCase(captureRepository);
  final getMemoriesUseCase = GetMemoriesUseCase(captureRepository);

  runApp(
    SecondBrainApp(
      captureRepository: captureRepository,
      saveMemoryUseCase: saveMemoryUseCase,
      getMemoriesUseCase: getMemoriesUseCase,
    ),
  );
}

class SecondBrainApp extends StatelessWidget {
  final CaptureRepositoryImpl captureRepository;
  final SaveMemoryUseCase saveMemoryUseCase;
  final GetMemoriesUseCase getMemoriesUseCase;

  const SecondBrainApp({
    super.key,
    required this.captureRepository,
    required this.saveMemoryUseCase,
    required this.getMemoriesUseCase,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CaptureBloc(
        saveMemoryUseCase: saveMemoryUseCase,
        getMemoriesUseCase: getMemoriesUseCase,
        repository: captureRepository,
      )..add(LoadMemoriesEvent()),
      child: MaterialApp(
        title: '2nd Brain',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const CaptureScreen(),
      ),
    );
  }
}
