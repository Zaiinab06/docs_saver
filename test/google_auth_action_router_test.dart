import 'package:flutter_test/flutter_test.dart';

/// Contract simulation of POST action routing in google-auth/index.ts.
///
/// This does not execute Deno. It documents the allowlist the Edge Function
/// must keep so Flutter `startGooglePicker()` cannot regress to
/// `Unknown action: start_picker`.
class GoogleAuthActionRouter {
  static const allowedActions = {
    'start',
    'start_picker',
    'status',
    'disconnect',
    'import_doc',
  };

  static String normalizeAction(dynamic rawAction) {
    if (rawAction is String && rawAction.trim().isNotEmpty) {
      return rawAction.trim();
    }
    return 'status';
  }

  static Map<String, dynamic> route({
    required dynamic action,
    String? mode,
    bool isPicker = false,
  }) {
    final normalized = normalizeAction(action);

    if (!allowedActions.contains(normalized)) {
      return {'status': 400, 'error': 'Unknown action: $normalized'};
    }

    if (normalized == 'start' || normalized == 'start_picker') {
      final picker =
          normalized == 'start_picker' || mode == 'picker' || isPicker;
      return {
        'status': 200,
        'success': true,
        'action': normalized,
        'isPicker': picker,
        'scope': picker
            ? 'https://www.googleapis.com/auth/drive.file'
            : 'https://www.googleapis.com/auth/drive.file email profile',
        'triggerOnepick': picker,
      };
    }

    return {'status': 200, 'action': normalized};
  }
}

void main() {
  group('google-auth POST action router contract', () {
    test('start_picker is an allowed action and is not Unknown action', () {
      final result = GoogleAuthActionRouter.route(action: 'start_picker');

      expect(result['status'], 200);
      expect(result['action'], 'start_picker');
      expect(result['error'], isNull);
      expect(
        result['error']?.toString(),
        isNot(equals('Unknown action: start_picker')),
      );
    });

    test('start_picker uses drive.file scope and trigger_onepick', () {
      final result = GoogleAuthActionRouter.route(action: 'start_picker');

      expect(result['isPicker'], isTrue);
      expect(result['triggerOnepick'], isTrue);
      expect(result['scope'], 'https://www.googleapis.com/auth/drive.file');
      expect(result['scope'], isNot(contains('email')));
      expect(result['scope'], isNot(contains('profile')));
    });

    test('start remains non-picker OAuth with email and profile scopes', () {
      final result = GoogleAuthActionRouter.route(action: 'start');

      expect(result['status'], 200);
      expect(result['action'], 'start');
      expect(result['isPicker'], isFalse);
      expect(result['triggerOnepick'], isFalse);
      expect(
        result['scope'],
        'https://www.googleapis.com/auth/drive.file email profile',
      );
    });

    test('status, disconnect, and import_doc remain allowed', () {
      for (final action in ['status', 'disconnect', 'import_doc']) {
        final result = GoogleAuthActionRouter.route(action: action);
        expect(result['status'], 200, reason: action);
        expect(result['action'], action);
      }
    });

    test('unknown actions still return Unknown action: <name>', () {
      final result = GoogleAuthActionRouter.route(action: 'not_a_real_action');

      expect(result['status'], 400);
      expect(result['error'], 'Unknown action: not_a_real_action');
    });

    test('whitespace around start_picker is trimmed and accepted', () {
      final result = GoogleAuthActionRouter.route(action: '  start_picker  ');

      expect(result['status'], 200);
      expect(result['action'], 'start_picker');
      expect(result['isPicker'], isTrue);
    });

    test('missing action defaults to status, not unknown', () {
      final result = GoogleAuthActionRouter.route(action: null);

      expect(result['status'], 200);
      expect(result['action'], 'status');
    });
  });
}
