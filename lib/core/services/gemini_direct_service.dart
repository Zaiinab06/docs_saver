import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart';
import '../constants/supabase_constants.dart';

/// Direct client-side Gemini AI service that acts as a fallback
/// when the Supabase Edge Function (process-ingestion) is unreachable or fails.
class GeminiDirectService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static String _extractKeyFromText(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('GEMINI_API_KEY=')) {
        final val = trimmed.substring('GEMINI_API_KEY='.length).trim();
        final clean = val.replaceAll('"', '').replaceAll("'", "");
        if (clean.isNotEmpty) {
          return clean;
        }
      }
    }
    return '';
  }

  /// Resolves the local Gemini API key from .env file, assets bundle,
  /// Platform environment, or compile-time Dart defines.
  static Future<String> resolveApiKey() async {
    // 1. Compile-time constant (--dart-define=GEMINI_API_KEY=...)
    if (SupabaseConstants.geminiApiKey.isNotEmpty) {
      return SupabaseConstants.geminiApiKey;
    }

    // 2. Read from local .env files (desktop / debug)
    final envPaths = ['.env', '../.env', 'assets/.env'];
    for (final path in envPaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          final key = _extractKeyFromText(content);
          if (key.isNotEmpty) {
            return key;
          }
        }
      } catch (_) {}
    }

    // 3. Read from Flutter asset bundle (on device)
    for (final assetPath in ['.env', 'assets/.env']) {
      try {
        final content = await rootBundle.loadString(assetPath);
        final key = _extractKeyFromText(content);
        if (key.isNotEmpty) {
          return key;
        }
      } catch (_) {}
    }

    // 4. Platform environment variable (Desktop / local dev)
    try {
      final envKey = Platform.environment['GEMINI_API_KEY'];
      if (envKey != null && envKey.trim().isNotEmpty) {
        return envKey.trim();
      }
    } catch (_) {}

    return '';
  }

  /// Directly invokes Gemini 1.5 Flash multimodal endpoint for image analysis.
  static Future<Map<String, dynamic>> analyzeDirect({
    required String ocrText,
    String? imageBase64,
    String? audioBase64,
    String? mimeType,
  }) async {
    final apiKey = await resolveApiKey();
    if (apiKey.isEmpty) {
      debugPrint('[GeminiDirectService] No local GEMINI_API_KEY found in .env, assets, or environment.');
      throw Exception('Local GEMINI_API_KEY not configured for client-side fallback.');
    }

    String cleanAudioBase64 = (audioBase64 ?? '').trim();
    if (cleanAudioBase64.contains(';base64,')) {
      cleanAudioBase64 = cleanAudioBase64.split(';base64,').last;
    }
    cleanAudioBase64 = cleanAudioBase64.replaceAll(RegExp(r'\s+'), '');
    final bool hasAudio = cleanAudioBase64.isNotEmpty;

    String cleanBase64 = (imageBase64 ?? '').trim();
    if (cleanBase64.contains(';base64,')) {
      cleanBase64 = cleanBase64.split(';base64,').last;
    }
    cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

    final bool hasImage = cleanBase64.isNotEmpty;

    debugPrint('[GeminiDirectService] Calling Gemini 1.5 Flash directly (hasAudio=$hasAudio, hasImage=$hasImage)...');

    final String promptText = hasAudio
        ? 'You are an expert speech recognition and audio transcription engine. Listen carefully to the attached audio and output clean structured JSON:\n'
          '{"title": "Short Title (3-6 words)", "category": "Work|Personal|Study|Travel|Fashion|Food|Finance|Health", "summary": "1-2 sentence concise summary of the useful meaning", "tags": ["tag1", "tag2", "voice"], "transcript": "verbatim transcription of spoken words"}\n'
          'Output ONLY valid raw JSON, no markdown formatting.'
        : (hasImage
            ? 'Analyze this image and describe exactly what is in it. Return a valid JSON object with: {"title": "Short Title (3-5 words)", "category": "Work|Personal|Study|Home", "summary": "2-sentence factual summary of what is seen", "tags": ["tag1", "tag2", "tag3"]}. Output ONLY raw JSON, no markdown formatting.'
            : 'Analyze the following note content:\n"""\n$ocrText\n"""\nGenerate a concise Title, Category (e.g., Food, Personal, Work, Study), a 2-sentence summary, and 3-5 tags in JSON format with keys: "title", "category", "summary", "tags". Output ONLY raw JSON, no markdown formatting.');

    final List<Map<String, dynamic>> parts = [
      {'text': promptText},
    ];

    if (hasAudio) {
      parts.add({
        'inline_data': {
          'mime_type': mimeType ?? 'audio/m4a',
          'data': cleanAudioBase64,
        },
      });
    } else if (hasImage) {
      parts.add({
        'inline_data': {
          'mime_type': mimeType ?? 'image/jpeg',
          'data': cleanBase64,
        },
      });
    }

    final payload = {
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      },
    };

    final candidateModels = [
      'gemini-1.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-flash-8b',
    ];

    DioException? lastDioError;
    for (final model in candidateModels) {
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
      try {
        Response response = await _dio.post(url, data: payload);

        // If Google API returns 400 for inline_data casing, retry with camelCase inlineData
        if (response.statusCode != 200 && response.data != null) {
          final errStr = response.data.toString();
          if (errStr.contains('inline_data') || errStr.contains('Cannot find field')) {
            final camelParts = parts.map((p) {
              if (p.containsKey('inline_data')) {
                final d = p['inline_data'] as Map;
                return {
                  'inlineData': {
                    'mimeType': d['mime_type'],
                    'data': d['data'],
                  }
                };
              }
              return p;
            }).toList();
            response = await _dio.post(url, data: {
              ...payload,
              'contents': [
                {'role': 'user', 'parts': camelParts}
              ]
            });
          }
        }

        if (response.statusCode == 200 && response.data != null) {
          final resData = response.data;
          final candidates = resData['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final partsList = content?['parts'] as List?;
            if (partsList != null && partsList.isNotEmpty) {
              final rawJsonText = partsList[0]['text']?.toString().trim() ?? '';
              debugPrint('AI DYNAMIC RESPONSE: $rawJsonText');

              String cleanJson = rawJsonText;
              if (cleanJson.startsWith('```json')) {
                cleanJson = cleanJson.replaceFirst(RegExp(r'^```json\s*'), '');
                cleanJson = cleanJson.replaceFirst(RegExp(r'\s*```$'), '');
              } else if (cleanJson.startsWith('```')) {
                cleanJson = cleanJson.replaceFirst(RegExp(r'^```\s*'), '');
                cleanJson = cleanJson.replaceFirst(RegExp(r'\s*```$'), '');
              }

              final parsed = jsonDecode(cleanJson);
              if (parsed is Map) {
                final Map<String, dynamic> result = Map<String, dynamic>.from(parsed);
                result['ai_status'] = 'processed';
                result['model'] = model;
                return result;
              }
            }
          }
        }
      } on DioException catch (de) {
        final errText = de.response?.data?.toString() ?? de.message ?? '';
        debugPrint('⚠️ [GeminiDirectService] Model $model failed (${de.response?.statusCode}): $errText');
        lastDioError = de;
      } catch (e) {
        debugPrint('⚠️ [GeminiDirectService] Unexpected error on $model: $e');
      }
    }

    throw Exception(
      'Client-side Gemini analysis failed on all candidate models: ${lastDioError?.message ?? "unknown error"}',
    );
  }
}
