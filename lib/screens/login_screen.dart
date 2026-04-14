import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../services/auth_service.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_localizations.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;
  String _errorMessage = '';

  // intl_phone_field에서 조합된 완전한 번호 (+821012345678 형태)
  String _completePhoneNumber = '';
  bool _phoneValid = false;

  static const _locales = [
    {'code': 'ko', 'label': '한국어'},
    {'code': 'en', 'label': 'English'},
    {'code': 'ja', 'label': '日本語'},
  ];

  // 앱 언어에 따라 초기 국가코드 설정
  String _initialCountryCode(String languageCode) {
    switch (languageCode) {
      case 'ko': return 'KR';
      case 'ja': return 'JP';
      default:   return 'US';
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _sendSms() async {
    final l = AppLocalizations.of(context);
    if (!_phoneValid || _completePhoneNumber.isEmpty) {
      setState(() => _errorMessage = l.loginPhoneError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    await context.read<AuthService>().verifyPhoneNumber(
      _completePhoneNumber,
      (error) => setState(() {
        _errorMessage = error;
        _isLoading = false;
      }),
      () => setState(() {
        _codeSent = true;
        _isLoading = false;
      }),
    );
  }

  void _verifyOtp() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final success = await context
        .read<AuthService>()
        .verifyOTP(_otpController.text.trim());

    if (!success && mounted) {
      setState(() {
        _errorMessage = l.loginInvalidOtp;
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await context.read<AuthService>().signInWithGoogle();

    if (!mounted) return;
    if (result == 'error') {
      setState(() {
        _errorMessage = l.loginGoogleFailed;
        _isLoading = false;
      });
    } else if (result == 'cancel') {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    final currentLocale = localeProvider.locale.languageCode;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 언어 선택 ────────────────────────────────────────────
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

              const SizedBox(height: 0),

              // ── 로고 ─────────────────────────────────────────────────
              Image.asset(
                'assets/images/answer_logo.png',
                height: 160,
                errorBuilder: (_, __, ___) => Icon(
                    Icons.chat_bubble_rounded,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 0),
              Text(
                l.loginTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),

              // ── Google 로그인 버튼 ────────────────────────────────────
              _SocialLoginButton(
                onPressed: _isLoading ? null : _signInWithGoogle,
                icon: Image.asset(
                  'assets/images/google_logo.png',
                  width: 20,
                  height: 20,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.g_mobiledata, size: 24),
                ),
                label: l.loginWithGoogle,
                backgroundColor: Theme.of(context).colorScheme.surface,
                textColor: Theme.of(context).colorScheme.onSurface,
                borderColor: Theme.of(context).colorScheme.outlineVariant,
              ),

              const SizedBox(height: 12),

              // ── Apple 로그인 버튼 (비활성) ───────────────────────────
              _SocialLoginButton(
                onPressed: null,
                icon: const Icon(Icons.apple,
                    size: 22, color: Colors.white),
                label: l.loginWithApple,
                backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                textColor: Colors.white,
                borderColor: Theme.of(context).colorScheme.inverseSurface,
                disabled: true,
              ),

              const SizedBox(height: 24),

              // ── 구분선 ────────────────────────────────────────────────
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(l.loginOr,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13)),
                ),
                const Expanded(child: Divider()),
              ]),

              const SizedBox(height: 24),

              // ── 전화번호 입력 / OTP 입력 ─────────────────────────────
              if (!_codeSent) ...[
                // intl_phone_field — 국가코드 셀렉터 + 번호 입력
                IntlPhoneField(
                  initialCountryCode:
                      _initialCountryCode(currentLocale),
                  decoration: InputDecoration(
                    labelText: l.loginPhoneLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (phone) {
                    _completePhoneNumber = phone.completeNumber;
                    _phoneValid = true;
                  },
                  onCountryChanged: (country) {
                    // 국가 변경 시 번호 초기화
                    _completePhoneNumber = '';
                    _phoneValid = false;
                  },
                  invalidNumberMessage: l.loginPhoneError,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendSms,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : Text(l.loginSendSms),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l.loginOtpLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.password),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : Text(l.loginVerify),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _codeSent = false;
                    _otpController.clear();
                    _errorMessage = '';
                    _completePhoneNumber = '';
                    _phoneValid = false;
                  }),
                  child: Text(l.loginBack),
                ),
              ],

              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),

              // ── 약관 동의 안내 문구 ──────────────────────────────────────
              const SizedBox(height: 24),
              Text(
                l.loginAgreeToTerms,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              // ── 회원가입으로 이동 ────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegistrationScreen()),
                  ),
                  child: Text(
                    l.goToRegister,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 소셜 로그인 버튼 ───────────────────────────────────────────────────────────
class _SocialLoginButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color borderColor;
  final bool disabled;

  const _SocialLoginButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
