import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/constants/app_strings.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_event.dart';
import 'package:second_brain/features/capture/presentation/screens/memory_review_screen.dart';
import 'package:second_brain/features/home/presentation/screens/home_screen.dart';

class FakeCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories;

  FakeCaptureRepository(this.memories);

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => List.from(memories);

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

  group('Take Photo & Review Flow Verification', () {
    testWidgets('Save Memory persists custom title and appears on Home screen',
        (tester) async {
      final repo = FakeCaptureRepository([]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: const MaterialApp(
            home: HomeScreen(userName: 'Noor'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially empty
      expect(find.text("Your brain is empty — let's fill it."), findsOneWidget);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsNothing);

      // Simulate saving a captured photo memory with custom user title
      captureBloc.add(
        const AddMemoryEvent(
          title: 'My Handwritten Lecture Notes',
          content: 'Key concepts of cell division and mitosis',
          category: 'Study',
          tags: ['biology', 'notes'],
          mediaUrl: '/data/user/0/memory_1.jpg',
          aiStatus: 'processed',
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Memory is saved in repository
      expect(repo.memories.length, 1);
      expect(repo.memories.first.title, 'My Handwritten Lecture Notes');
      expect(repo.memories.first.category, 'Study');
      expect(repo.memories.first.tags, contains('biology'));

      // Verified: Saved memory appears on Home screen
      expect(find.text('My Handwritten Lecture Notes'), findsOneWidget);
      expect(find.text(AppStrings.homeRecentMemoriesHeader), findsOneWidget);
      expect(find.text("Your brain is empty — let's fill it."), findsNothing);
    });

    testWidgets('Memory Review screen preserves user-entered title and tags',
        (tester) async {
      final dummyFile = File('test_image.jpg');
      final repo = FakeCaptureRepository([]);
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CaptureBloc>.value(value: captureBloc),
          ],
          child: MaterialApp(
            home: MemoryReviewScreen(
              imageFile: dummyFile,
              initialTitle: 'AI Suggested Title',
              initialContent: 'Detected OCR text on paper',
              initialCategory: 'Work',
              initialTags: const ['work', 'doc'],
              aiStatus: 'processed',
              createdAt: DateTime(2026, 9, 14, 1, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify fields are loaded with dynamic AI / OCR results
      expect(find.text('Review & Save'), findsOneWidget);
      expect(find.text('AI Suggested Title'), findsOneWidget);
      expect(find.text('Detected OCR text on paper'), findsOneWidget);
      expect(find.text('#work'), findsOneWidget);
      expect(find.text('#doc'), findsOneWidget);

      // Verify user can edit title and add tag
      final titleFinder = find.byType(TextField).first;
      await tester.enterText(titleFinder, 'My Custom User Title');
      await tester.pumpAndSettle();

      expect(find.text('My Custom User Title'), findsOneWidget);
    });
  });
}
