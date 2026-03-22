import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_localizations.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  late TextEditingController _nameController;
  String _selectedTimezone = 'Asia/Seoul';
  bool _isLoading = false;

  static const _locales = [
    {'code': 'ko', 'label': '한국어'},
    {'code': 'en', 'label': 'English'},
    {'code': 'ja', 'label': '日本語'},
  ];

  static const _timezones = [
    'Asia/Seoul',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'America/New_York',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Paris',
  ];

  @override
  void initState() {
    super.initState();
    // Google 로그인이면 displayName 자동 입력
    final authService = context.read<AuthService>();
    _nameController = TextEditingController(
      text: authService.pendingDisplayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _register() async {
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.registerNameEmpty)),
      );
      return;
    }

    setState(() => _isLoading = true);

    final localeCode = context.read<LocaleProvider>().locale.languageCode;

    final success = await context.read<AuthService>().registerUser(
      name: name,
      locale: localeCode,
      timezone: _selectedTimezone,
    );

    if (!success && mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).registerFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    final currentLocale = localeProvider.locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l.registerTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 언어 선택 ──────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<String>(
                value: currentLocale,
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.language, size: 18),
                items: _locales.map((loc) {
                  return DropdownMenuItem(
                    value: loc['code'],
                    child: Text(loc['label']!,
                        style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (code) {
                  if (code != null) {
                    localeProvider.setLocale(Locale(code));
                  }
                },
              ),
            ),

            const SizedBox(height: 8),

            Text(
              l.registerWelcome,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(l.registerSubtitle),
            const SizedBox(height: 32),

            // ── 이름 입력 ──────────────────────────────────────────────
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l.registerNameLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),

            // ── 타임존 선택 ────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _selectedTimezone,
              decoration: InputDecoration(
                labelText: l.registerTimezone,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.access_time),
              ),
              items: _timezones
                  .map((tz) =>
                      DropdownMenuItem(value: tz, child: Text(tz)))
                  .toList(),
              onChanged: (val) =>
                  setState(() => _selectedTimezone = val!),
            ),
            const SizedBox(height: 32),

            // ── 등록 버튼 ──────────────────────────────────────────────
            ElevatedButton(
              onPressed: _isLoading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      l.registerComplete,
                      style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}