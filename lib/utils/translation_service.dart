import 'package:flutter/material.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  static const double _minConfidence = 0.5;
  static const Duration _translationTimeout = Duration(seconds: 10);

  // ── 언어 식별 ─────────────────────────────────────────────────────────────
  static Future<String?> identifyLanguage(String text) async {
    final languageIdentifier = LanguageIdentifier(
      confidenceThreshold: _minConfidence,
    );
    try {
      final result = await languageIdentifier.identifyLanguage(text);
      return (result == 'und' || result.isEmpty) ? null : result.split('-').first.toLowerCase();
    } catch (e) {
      debugPrint('언어 식별 실패: $e');
      return null;
    } finally {
      languageIdentifier.close();
    }
  }

  // ── 언어 코드 매핑 (간소화) ──────────────────────────────────────────────────
  static TranslateLanguage getTranslateLanguage(String langCode) {
    switch (langCode) {
      case 'ko': return TranslateLanguage.korean;
      case 'ja': return TranslateLanguage.japanese;
      default: return TranslateLanguage.english;
    }
  }

  // ── 번역 ─────────────────────────────────────────────────────────────────
  static Future<String?> translateText({
    required String text,
    required String sourceLangCode,
    required String targetLangCode,
  }) async {
    final sourceLang = getTranslateLanguage(sourceLangCode);
    final targetLang = getTranslateLanguage(targetLangCode);
    
    final translator = OnDeviceTranslator(
      sourceLanguage: sourceLang,
      targetLanguage: targetLang,
    );

    try {
      final modelManager = OnDeviceTranslatorModelManager();
      
      // 모델 다운로드 체크
      if (!await modelManager.isModelDownloaded(sourceLang.bcpCode)) {
        await modelManager.downloadModel(sourceLang.bcpCode, isWifiRequired: false);
      }
      if (!await modelManager.isModelDownloaded(targetLang.bcpCode)) {
        await modelManager.downloadModel(targetLang.bcpCode, isWifiRequired: false);
      }

      return await translator.translateText(text).timeout(_translationTimeout);
    } catch (e) {
      debugPrint('번역 실패: $e');
      return null;
    } finally {
      translator.close();
    }
  }
}
