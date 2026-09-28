import 'package:flutter_test/flutter_test.dart';

/// Contract simulation of the safe /callback logic implemented in google-auth/index.ts.
///
/// NOTE ON TEST LIMITATION:
/// This Dart test suite simulates the contract and behavioral logic of the backend
/// Edge Function callback. It executes within the Flutter test runner to verify
/// state preservation, failure aborts, and URL parameter safety. It does NOT directly
/// execute the TypeScript/Deno runtime of Supabase Edge Functions.
class CallbackSafetyHandler {
  static Map<String, dynamic> processCallback({
    required Map<String, dynamic>? existingIntegration,
    required String? newRefreshToken,
    required String? newIdTokenEmail,
    required String? newIdTokenName,
    required bool tokenExchangeSuccess,
    required bool vaultStorageSuccess,
    required String? mockNewVaultSecretId,
    bool existingIntegrationQueryError = false,
  }) {
    if (!tokenExchangeSuccess) {
      return {
        'status': 302,
        'redirect':
            'secondbrain://oauth/callback?status=error&reason=token_exchange_failed',
        'modifiedIntegration': existingIntegration,
        'vaultStored': false,
        'upsertAttempted': false,
      };
    }

    // 1. Fetch existing integration row to preserve values on re-authorization
    // If querying existing integration fails with a DB error, abort immediately.
    if (existingIntegrationQueryError) {
      return {
        'status': 302,
        'redirect':
            'secondbrain://oauth/callback?status=error&reason=database_error',
        'modifiedIntegration': existingIntegration,
        'vaultStored': false,
        'upsertAttempted': false,
      };
    }

    String? vaultSecretId =
        existingIntegration?['vault_refresh_token_id'] as String?;
    bool vaultStored = false;
    String? vaultOperation;

    // 2. Preserve or update Vault refresh token
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      if (!vaultStorageSuccess || mockNewVaultSecretId == null) {
        return {
          'status': 302,
          'redirect':
              'secondbrain://oauth/callback?status=error&reason=vault_storage_failed',
          'modifiedIntegration': existingIntegration,
          'vaultStored': false,
          'upsertAttempted': false,
        };
      }
      vaultOperation = vaultSecretId == null ? 'create' : 'update';
      vaultSecretId ??= mockNewVaultSecretId;
      vaultStored = true;
    }

    // If neither a new refresh token nor an existing Vault secret exists, abort
    if (vaultSecretId == null) {
      return {
        'status': 302,
        'redirect':
            'secondbrain://oauth/callback?status=error&reason=missing_refresh_token',
        'modifiedIntegration': existingIntegration,
        'vaultStored': vaultStored,
        'upsertAttempted': false,
      };
    }

    // 3. Preserve or update account details
    final finalEmail =
        newIdTokenEmail ?? existingIntegration?['account_email'] as String?;
    final finalName =
        newIdTokenName ?? existingIntegration?['account_name'] as String?;

    // 4. Resulting integration record
    final updatedIntegration = {
      'provider': 'google_drive',
      'account_email': finalEmail,
      'account_name': finalName,
      'scopes': [
        'https://www.googleapis.com/auth/drive.readonly',
        'https://www.googleapis.com/auth/drive.file',
      ],
      'status': 'connected',
      'vault_refresh_token_id': vaultSecretId,
    };

    return {
      'status': 302,
      'redirect': 'secondbrain://oauth/callback?status=success',
      'modifiedIntegration': updatedIntegration,
      'vaultStored': vaultStored,
      'vaultOperation': vaultOperation,
      'upsertAttempted': true,
    };
  }
}

void main() {
  group('Google OAuth Callback Safety & Preservation Tests', () {
    const existingVaultSecretId = 'vault-sec-1111-2222-3333';
    const newVaultSecretId = 'vault-sec-9999-8888-7777';
    const existingEmail = 'user@example.com';
    const existingName = 'Existing User';

    final existingIntegration = {
      'vault_refresh_token_id': existingVaultSecretId,
      'account_email': existingEmail,
      'account_name': existingName,
      'status': 'connected',
    };

    test('Existing refresh_token + new refresh_token updates in place', () {
      final result = CallbackSafetyHandler.processCallback(
        existingIntegration: existingIntegration,
        newRefreshToken: 'new_google_refresh_token_12345',
        newIdTokenEmail: existingEmail,
        newIdTokenName: existingName,
        tokenExchangeSuccess: true,
        vaultStorageSuccess: true,
        mockNewVaultSecretId: newVaultSecretId,
      );

      expect(result['status'], equals(302));
      expect(
        result['redirect'],
        equals('secondbrain://oauth/callback?status=success'),
      );
      expect(
        result['modifiedIntegration']['vault_refresh_token_id'],
        equals(existingVaultSecretId),
      );
      expect(result['vaultOperation'], equals('update'));
      expect(
        result['modifiedIntegration']['account_email'],
        equals(existingEmail),
      );
      expect(result['modifiedIntegration']['status'], equals('connected'));
    });

    test(
      'Concurrent OAuth callbacks preserve one existing Vault secret ID',
      () {
        final firstResult = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'first_new_refresh_token',
          newIdTokenEmail: existingEmail,
          newIdTokenName: existingName,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
        );
        final secondResult = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'second_new_refresh_token',
          newIdTokenEmail: existingEmail,
          newIdTokenName: existingName,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
        );

        expect(firstResult['vaultOperation'], equals('update'));
        expect(secondResult['vaultOperation'], equals('update'));
        expect(
          firstResult['modifiedIntegration']['vault_refresh_token_id'],
          equals(secondResult['modifiedIntegration']['vault_refresh_token_id']),
        );
      },
    );

    test(
      'Existing refresh_token + NO new refresh_token returned preserves existing Vault secret ID',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: null, // Google did not return a new refresh token
          newIdTokenEmail: null,
          newIdTokenName: null,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: null,
        );

        expect(result['status'], equals(302));
        expect(
          result['redirect'],
          equals('secondbrain://oauth/callback?status=success'),
        );
        // Must NOT be null; must preserve existingVaultSecretId
        expect(
          result['modifiedIntegration']['vault_refresh_token_id'],
          equals(existingVaultSecretId),
        );
        expect(
          result['modifiedIntegration']['account_email'],
          equals(existingEmail),
        );
        expect(
          result['modifiedIntegration']['account_name'],
          equals(existingName),
        );
      },
    );

    test('Existing email/name + new email/name returned updates values', () {
      const updatedEmail = 'new_email@example.com';
      const updatedName = 'New Name';

      final result = CallbackSafetyHandler.processCallback(
        existingIntegration: existingIntegration,
        newRefreshToken: null,
        newIdTokenEmail: updatedEmail,
        newIdTokenName: updatedName,
        tokenExchangeSuccess: true,
        vaultStorageSuccess: true,
        mockNewVaultSecretId: null,
      );

      expect(
        result['modifiedIntegration']['account_email'],
        equals(updatedEmail),
      );
      expect(
        result['modifiedIntegration']['account_name'],
        equals(updatedName),
      );
      expect(
        result['modifiedIntegration']['vault_refresh_token_id'],
        equals(existingVaultSecretId),
      );
    });

    test(
      'Existing email/name + NULL new email/name preserves existing email/name',
      () {
        // In drive.file-only Picker flow, id_token is omitted so email/name are null
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: null,
          newIdTokenEmail: null,
          newIdTokenName: null,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: null,
        );

        expect(
          result['modifiedIntegration']['account_email'],
          equals(existingEmail),
        );
        expect(
          result['modifiedIntegration']['account_name'],
          equals(existingName),
        );
        expect(
          result['modifiedIntegration']['vault_refresh_token_id'],
          equals(existingVaultSecretId),
        );
      },
    );

    test(
      'Failed token exchange preserves existing integration without modification',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'some_token',
          newIdTokenEmail: 'other@example.com',
          newIdTokenName: 'Other',
          tokenExchangeSuccess: false, // Exchange failed with Google
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
        );

        expect(result['status'], equals(302));
        expect(result['redirect'], contains('reason=token_exchange_failed'));
        expect(result['modifiedIntegration'], equals(existingIntegration));
      },
    );

    test(
      'Vault storage failure does not corrupt or overwrite integration record',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'new_token',
          newIdTokenEmail: existingEmail,
          newIdTokenName: existingName,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: false, // Vault RPC errored
          mockNewVaultSecretId: null,
        );

        expect(result['status'], equals(302));
        expect(result['redirect'], contains('reason=vault_storage_failed'));
        expect(result['modifiedIntegration'], equals(existingIntegration));
      },
    );

    test(
      'First-time connection with NO refresh token aborts with error instead of null vault_id',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: null, // First time, no existing record
          newRefreshToken: null, // Google failed to return refresh token
          newIdTokenEmail: 'first@example.com',
          newIdTokenName: 'First User',
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: null,
        );

        expect(result['status'], equals(302));
        expect(result['redirect'], contains('reason=missing_refresh_token'));
        expect(result['modifiedIntegration'], isNull);
      },
    );

    test(
      'Deep link URL never contains authorization codes, access tokens, or refresh tokens',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'secret_refresh_token_999',
          newIdTokenEmail: existingEmail,
          newIdTokenName: existingName,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
        );

        final redirectUrl = result['redirect'] as String;
        expect(redirectUrl, isNot(contains('secret_refresh_token')));
        expect(redirectUrl, isNot(contains('code=')));
        expect(redirectUrl, isNot(contains('access_token')));
        expect(
          redirectUrl,
          equals('secondbrain://oauth/callback?status=success'),
        );
      },
    );

    test(
      'Database read error stops callback processing with database_error reason',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'some_new_refresh_token',
          newIdTokenEmail: null,
          newIdTokenName: null,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
          existingIntegrationQueryError: true, // Database query failed
        );

        expect(result['status'], equals(302));
        expect(
          result['redirect'],
          equals(
            'secondbrain://oauth/callback?status=error&reason=database_error',
          ),
        );
      },
    );

    test(
      'Database read error does not call Vault storage or upsert user_integrations',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'some_new_refresh_token',
          newIdTokenEmail: 'new@example.com',
          newIdTokenName: 'New Name',
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
          existingIntegrationQueryError: true,
        );

        expect(result['vaultStored'], isFalse);
        expect(result['upsertAttempted'], isFalse);
      },
    );

    test(
      'Database read error does not erase or modify existing account details',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: existingIntegration,
          newRefreshToken: 'some_new_refresh_token',
          newIdTokenEmail: null, // No id_token
          newIdTokenName: null,
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
          existingIntegrationQueryError: true,
        );

        // Must preserve the existing integration record unchanged
        expect(result['modifiedIntegration'], equals(existingIntegration));
        expect(
          result['modifiedIntegration']['account_email'],
          equals(existingEmail),
        );
        expect(
          result['modifiedIntegration']['account_name'],
          equals(existingName),
        );
        expect(
          result['modifiedIntegration']['vault_refresh_token_id'],
          equals(existingVaultSecretId),
        );
      },
    );

    test(
      'Valid empty query result follows existing first-time authorization flow',
      () {
        final result = CallbackSafetyHandler.processCallback(
          existingIntegration: null, // Valid query returning no row
          newRefreshToken: 'first_time_refresh_token',
          newIdTokenEmail: 'first@example.com',
          newIdTokenName: 'First User',
          tokenExchangeSuccess: true,
          vaultStorageSuccess: true,
          mockNewVaultSecretId: newVaultSecretId,
          existingIntegrationQueryError: false,
        );

        expect(result['status'], equals(302));
        expect(
          result['redirect'],
          equals('secondbrain://oauth/callback?status=success'),
        );
        expect(result['vaultStored'], isTrue);
        expect(result['vaultOperation'], equals('create'));
        expect(result['upsertAttempted'], isTrue);
        expect(
          result['modifiedIntegration']['vault_refresh_token_id'],
          equals(newVaultSecretId),
        );
        expect(
          result['modifiedIntegration']['account_email'],
          equals('first@example.com'),
        );
        expect(
          result['modifiedIntegration']['account_name'],
          equals('First User'),
        );
      },
    );
  });
}
