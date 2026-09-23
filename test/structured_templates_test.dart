import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:second_brain/features/capture/domain/entities/memory_entity.dart';
import 'package:second_brain/features/capture/domain/entities/structured_template.dart';
import 'package:second_brain/features/capture/data/models/memory_model.dart';
import 'package:second_brain/features/capture/domain/repositories/capture_repository.dart';
import 'package:second_brain/features/capture/domain/usecases/save_memory_usecase.dart';
import 'package:second_brain/features/capture/domain/usecases/get_memories_usecase.dart';
import 'package:second_brain/features/capture/presentation/bloc/capture_bloc.dart';
import 'package:second_brain/features/capture/presentation/widgets/bank_card_display_card.dart';
import 'package:second_brain/features/capture/presentation/widgets/bill_display_card.dart';
import 'package:second_brain/features/capture/presentation/widgets/bank_card_template_sheet.dart';
import 'package:second_brain/features/capture/presentation/widgets/bill_template_sheet.dart';

class MockCaptureRepository implements CaptureRepository {
  final List<MemoryEntity> memories = [];

  @override
  Future<List<MemoryEntity>> getMemories({String? userId}) async => memories;

  @override
  Future<void> saveMemory(MemoryEntity memory) async {
    memories.add(memory);
  }

  @override
  Future<void> syncPendingMemories({String? userId}) async {}

  @override
  Stream<MemoryEntity> subscribeToMemoryUpdates(String userId) =>
      const Stream.empty();

  @override
  Future<void> deleteMemory(String memoryId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Structured Templates — Domain & Serialization Unit Tests', () {
    test('BankCardTemplate formats and masks card numbers accurately', () {
      const rawNumber = '1234567890123456';
      final formatted = BankCardTemplate.formatCardNumber(rawNumber);
      expect(formatted, '1234 5678 9012 3456');

      final masked = BankCardTemplate.maskCardNumber(formatted);
      expect(masked, '•••• •••• •••• 3456');

      const template = BankCardTemplate(
        cardholderName: 'Zainab Khan',
        cardNumber: '1234 5678 9012 3456',
        bankName: 'Meezan Bank',
        cardType: 'Visa',
        expiryDate: '12/28',
        notes: 'Payroll account',
      );

      expect(template.last4, '3456');
      expect(template.maskedCardNumber, '•••• •••• •••• 3456');

      final markdown = template.toMarkdownBody();
      expect(markdown, contains('Meezan Bank'));
      expect(markdown, contains('Visa'));
      expect(markdown, contains('Zainab Khan'));
      expect(markdown, contains('•••• •••• •••• 3456'));
      expect(markdown, contains('12/28'));
      expect(markdown, contains('Payroll account'));

      final serialized = template.toSerializedContent();
      expect(serialized, contains('<!--template_metadata:'));
      expect(serialized, contains('"template":"bank_card"'));
    });

    test('BillTemplate formats markdown and serializes metadata accurately', () {
      const bill = BillTemplate(
        billType: 'Electricity',
        consumerNumber: '08 12345 6789012',
        amount: 'PKR 14,500',
        dueDate: '2026-10-15',
        isPaid: false,
        notes: 'Monthly utility',
      );

      final markdown = bill.toMarkdownBody();
      expect(markdown, contains('Electricity'));
      expect(markdown, contains('08 12345 6789012'));
      expect(markdown, contains('PKR 14,500'));
      expect(markdown, contains('2026-10-15'));
      expect(markdown, contains('Unpaid ⏳'));

      final paidBill = bill.copyWith(isPaid: true);
      expect(paidBill.isPaid, isTrue);
      expect(paidBill.toMarkdownBody(), contains('Paid ✅'));

      final serialized = bill.toSerializedContent();
      expect(serialized, contains('<!--template_metadata:'));
      expect(serialized, contains('"template":"bill"'));
    });

    test('MemoryEntity cleanly extracts template data and clean content', () {
      const template = BankCardTemplate(
        cardholderName: 'Noor Fatima',
        cardNumber: '4111 2222 3333 4444',
        bankName: 'Standard Chartered',
        cardType: 'Mastercard',
        expiryDate: '06/29',
      );

      final serializedContent = template.toSerializedContent();
      final now = DateTime.now();

      final memory = MemoryEntity(
        id: 'mem-card-1',
        userId: 'user-1',
        title: 'Standard Chartered Mastercard (•••• 4444)',
        content: serializedContent,
        category: 'Finance',
        tags: const ['#card', '#finance'],
        clientCreatedAt: now,
        clientUpdatedAt: now,
        serverUpdatedAt: now,
      );

      expect(memory.isStructuredTemplate, isTrue);
      expect(memory.templateType, TemplateTypes.bankCard);
      expect(memory.bankCardTemplate, isNotNull);
      expect(memory.bankCardTemplate!.cardholderName, 'Noor Fatima');
      expect(memory.bankCardTemplate!.bankName, 'Standard Chartered');
      expect(memory.bankCardTemplate!.last4, '4444');
      expect(memory.cleanContent, isNot(contains('<!--template_metadata:')));
    });

    test('MemoryModel fromMap preserves and maps template metadata', () {
      const bill = BillTemplate(
        billType: 'Internet',
        consumerNumber: 'NET-998877',
        amount: 'PKR 3,500',
        dueDate: '2026-10-01',
        isPaid: true,
      );

      final map = {
        'id': 'mem-bill-1',
        'user_id': 'user-1',
        'title': 'Internet Bill (NET-998877)',
        'content': bill.toSerializedContent(),
        'category': 'Finance',
        'tags': ['#bill', '#internet', '#paid'],
        'client_created_at': DateTime.now().toIso8601String(),
        'client_updated_at': DateTime.now().toIso8601String(),
        'server_updated_at': DateTime.now().toIso8601String(),
      };

      final model = MemoryModel.fromMap(map);
      final entity = model.toEntity();

      expect(entity.isStructuredTemplate, isTrue);
      expect(entity.templateType, TemplateTypes.bill);
      expect(entity.billTemplate, isNotNull);
      expect(entity.billTemplate!.consumerNumber, 'NET-998877');
      expect(entity.billTemplate!.amount, 'PKR 3,500');
      expect(entity.billTemplate!.isPaid, isTrue);
    });
  });

  group('Structured Templates — Widget Display & Interaction Tests', () {
    testWidgets('BankCardDisplayCard renders all banking details properly', (
      tester,
    ) async {
      const template = BankCardTemplate(
        cardholderName: 'Zainab Khan',
        cardNumber: '5555 4444 3333 2222',
        bankName: 'Bank Alfalah',
        cardType: 'Visa',
        expiryDate: '10/27',
        notes: 'Main business card',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BankCardDisplayCard(template: template)),
        ),
      );

      expect(find.text('Bank Alfalah'), findsOneWidget);
      expect(find.text('VISA'), findsOneWidget);
      expect(find.text('•••• •••• •••• 2222'), findsOneWidget);
      expect(find.text('ZAINAB KHAN'), findsOneWidget);
      expect(find.text('10/27'), findsOneWidget);
      expect(find.text('Main business card'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets(
      'BillDisplayCard renders details and triggers onTogglePaid',
      (tester) async {
        bool toggledValue = false;
        const template = BillTemplate(
          billType: 'Gas',
          consumerNumber: 'SNGPL-77665544',
          amount: 'PKR 2,400',
          dueDate: '2026-11-20',
          isPaid: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BillDisplayCard(
                template: template,
                onTogglePaid: (val) {
                  toggledValue = val;
                },
              ),
            ),
          ),
        );

        expect(find.text('Gas Bill'), findsOneWidget);
        expect(find.text('PKR 2,400'), findsOneWidget);
        expect(find.text('SNGPL-77665544'), findsOneWidget);
        expect(find.text('Due Date: 2026-11-20'), findsOneWidget);
        expect(find.text('UNPAID'), findsOneWidget);

        // Tap toggle badge
        await tester.tap(find.text('UNPAID'));
        await tester.pumpAndSettle();

        expect(toggledValue, isTrue);
      },
    );

    testWidgets('BankCardTemplateSheet collects data and saves memory', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(414, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = MockCaptureRepository();
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: const MaterialApp(home: Scaffold(body: BankCardTemplateSheet())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save Bank Card'), findsOneWidget);
      expect(find.text('Cardholder Name'), findsOneWidget);

      // Enter cardholder
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. ZAINAB KHAN'),
        'ALICE SMITH',
      );

      // Enter card number
      await tester.enterText(
        find.widgetWithText(TextFormField, '•••• •••• •••• 1234'),
        '4242424242424242',
      );

      // Enter expiry
      await tester.enterText(
        find.widgetWithText(TextFormField, 'MM/YY'),
        '05/29',
      );

      await tester.pumpAndSettle();

      // Scroll to Save button and tap
      final saveBtn = find.text('Save Card to Memory');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify repository received the memory
      expect(repo.memories.length, 1);
      final saved = repo.memories.first;
      expect(saved.category, 'Finance');
      expect(saved.isStructuredTemplate, isTrue);
      expect(saved.bankCardTemplate!.cardholderName, 'ALICE SMITH');
      expect(saved.bankCardTemplate!.last4, '4242');
      expect(saved.bankCardTemplate!.expiryDate, '05/29');
    });

    testWidgets('BillTemplateSheet collects data and saves bill memory', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(414, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = MockCaptureRepository();
      final captureBloc = CaptureBloc(
        saveMemoryUseCase: SaveMemoryUseCase(repo),
        getMemoriesUseCase: GetMemoriesUseCase(repo),
        repository: repo,
      );

      await tester.pumpWidget(
        BlocProvider<CaptureBloc>.value(
          value: captureBloc,
          child: const MaterialApp(home: Scaffold(body: BillTemplateSheet())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save Utility / Bill'), findsOneWidget);

      // Switch to Internet bill type
      await tester.tap(find.text('Internet'));
      await tester.pumpAndSettle();

      // Enter consumer number
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. 08 11234 5678901 U'),
        'PTCL-55443322',
      );

      // Enter amount
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. PKR 12,450'),
        'PKR 4,200',
      );

      // Toggle Paid switch
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Scroll to Save button and tap
      final saveBtn = find.text('Save Bill to Memory');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify repository received the bill
      expect(repo.memories.length, 1);
      final saved = repo.memories.first;
      expect(saved.category, 'Finance');
      expect(saved.isStructuredTemplate, isTrue);
      expect(saved.billTemplate!.billType, 'Internet');
      expect(saved.billTemplate!.consumerNumber, 'PTCL-55443322');
      expect(saved.billTemplate!.amount, 'PKR 4,200');
      expect(saved.billTemplate!.isPaid, isTrue);
      expect(saved.tags, contains('#paid'));
    });
  });
}
