import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../l10n/app_localizations.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String _content = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadMarkdown();
  }

  Future<void> _loadMarkdown() async {
    final lang = Localizations.localeOf(context).languageCode;
    // 지원하는 언어 없으면 영어로 폴백
    final code = ['ko', 'en', 'ja'].contains(lang) ? lang : 'en';
    final content = await rootBundle
        .loadString('assets/markdown/privacy_$code.md');
    if (mounted) setState(() => _content = content);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.termsOfService)),
      body: _content.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Markdown(
              data: _content,
              padding: const EdgeInsets.all(20),
              styleSheet: MarkdownStyleSheet(
                h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                p: const TextStyle(fontSize: 13, height: 1.7),
              ),
            ),
    );
  }
}