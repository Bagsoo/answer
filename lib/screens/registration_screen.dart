import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_localizations.dart';
import 'terms_screen.dart';
import 'privacy_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  late TextEditingController _nameController;
  String _selectedTimezone = 'Asia/Seoul';
  bool _isLoading = false;
  bool _termsAgreed = false;
  bool _privacyAgreed = false;

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
      termsAgreed: _termsAgreed,
      privacyAgreed: _privacyAgreed,
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
    final canRegister = _termsAgreed && _privacyAgreed && !_isLoading;

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
            const SizedBox(height: 28),

            // ── 약관 동의 ──────────────────────────────────────────────
            _AgreementRow(
              value: _termsAgreed,
              onChanged: (v) => setState(() => _termsAgreed = v ?? false),
              label: l.termsOfService,
              onDetailTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TermsScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _AgreementRow(
              value: _privacyAgreed,
              onChanged: (v) =>
                  setState(() => _privacyAgreed = v ?? false),
              label: l.privacyPolicy,
              onDetailTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              ),
            ),
            const SizedBox(height: 24),

            // ── 등록 버튼 ──────────────────────────────────────────────
            ElevatedButton(
              onPressed: canRegister ? _register : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                disabledBackgroundColor: Colors.amber.withOpacity(0.4),
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

// ── 약관 동의 행 ───────────────────────────────────────────────────────────────
class _AgreementRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final VoidCallback onDetailTap;

  const _AgreementRow({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.onDetailTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.amber,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: onDetailTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: colorScheme.primary,
          ),
          child: Text(
            l.viewDetails,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}