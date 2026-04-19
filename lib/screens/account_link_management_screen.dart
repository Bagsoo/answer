import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart' as intl_phone;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';

class AccountLinkManagementScreen extends StatefulWidget {
  const AccountLinkManagementScreen({super.key});

  @override
  State<AccountLinkManagementScreen> createState() =>
      _AccountLinkManagementScreenState();
}

class _AccountLinkManagementScreenState extends State<AccountLinkManagementScreen> {
  bool _busy = false;
  bool _phoneCodeSent = false;
  bool _phoneValid = false;
  String _completePhoneNumber = '';
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsController = TextEditingController();

  static const _google = 'google.com';
  static const _apple = 'apple.com';
  static const _phone = 'phone';

  String _label(String providerId) {
    switch (providerId) {
      case _google:
        return 'Google';
      case _apple:
        return 'Apple';
      case _phone:
        return 'Phone';
      default:
        return providerId;
    }
  }

  bool get _isPhoneLinkSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String _initialCountryCode(String languageCode) {
    switch (languageCode) {
      case 'ko':
        return 'KR';
      case 'ja':
        return 'JP';
      default:
        return 'US';
    }
  }

  Future<void> _showMessage(String text) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _linkGoogle() async {
    setState(() => _busy = true);
    final error = await context.read<AuthService>().linkGoogleProvider();
    await FirebaseAuth.instance.currentUser?.reload();
    if (!mounted) return;
    setState(() => _busy = false);

    if (error == null) {
      await _showMessage('Google 계정이 연결되었습니다.');
      return;
    }
    if (error == 'cancel') return;
    await _showMessage(error);
  }

  Future<void> _unlinkProvider(String providerId) async {
    setState(() => _busy = true);
    final error = await context.read<AuthService>().unlinkProvider(providerId);
    await FirebaseAuth.instance.currentUser?.reload();
    if (!mounted) return;
    setState(() => _busy = false);

    if (error == null) {
      await _showMessage('${_label(providerId)} 연결이 해제되었습니다.');
      return;
    }
    await _showMessage(error);
  }

  Future<void> _setPreferred(String providerId) async {
    setState(() => _busy = true);
    final error =
        await context.read<AuthService>().setPreferredLoginProvider(providerId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (error == null) {
      await _showMessage('기본 로그인 수단이 변경되었습니다.');
      return;
    }
    await _showMessage(error);
  }

  Future<void> _sendPhoneCode() async {
    final l = AppLocalizations.of(context);
    if (!_phoneValid || _completePhoneNumber.isEmpty) {
      await _showMessage(l.loginPhoneError);
      return;
    }

    setState(() => _busy = true);
    await context.read<AuthService>().verifyPhoneNumber(
      _completePhoneNumber,
      (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showMessage(e);
      },
      () {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _phoneCodeSent = true;
        });
        _showMessage(l.loginSendSms);
      },
      onAutoLinked: () {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _phoneCodeSent = false;
          _phoneController.clear();
          _smsController.clear();
          _phoneValid = false;
          _completePhoneNumber = '';
        });
        _showMessage(l.settingsSaved);
      },
    );
  }

  Future<void> _verifyPhoneCode() async {
    final l = AppLocalizations.of(context);
    final sms = _smsController.text.trim();
    if (sms.isEmpty) {
      await _showMessage(l.loginInvalidOtp);
      return;
    }
    setState(() => _busy = true);
    final error = await context.read<AuthService>().verifyOTP(sms);
    await FirebaseAuth.instance.currentUser?.reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _phoneCodeSent = false;
        _phoneController.clear();
        _smsController.clear();
        _phoneValid = false;
        _completePhoneNumber = '';
      }
    });
    await _showMessage(error ?? l.settingsSaved);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.sectionAccount)),
        body: Center(child: Text(l.logoutConfirm)),
      );
    }

    final providerIds = user.providerData
        .map((p) => p.providerId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final canUnlinkAny = providerIds.length > 1;

    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: Text(l.sectionAccount)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? const <String, dynamic>{};
          final preferred = (data['preferred_login_provider'] as String?) ?? '';
          final lastSignIn = (data['last_sign_in_provider'] as String?) ?? '';
          final phoneNumber = (data['phone_number'] as String?) ?? '';

          final linkedProviders = <String>[];
          if (providerIds.contains(_google)) linkedProviders.add(_google);
          if (providerIds.contains(_apple)) linkedProviders.add(_apple);
          if (providerIds.contains(_phone)) linkedProviders.add(_phone);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('마지막 로그인: ${lastSignIn.isEmpty ? '-' : _label(lastSignIn)}'),
                      const SizedBox(height: 8),
                      Text(
                        '기본 로그인: ${preferred.isEmpty ? '-' : _label(preferred)}',
                      ),
                      if (phoneNumber.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('연결된 전화번호: $phoneNumber'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _providerTile(
                title: 'Google',
                linked: providerIds.contains(_google),
                busy: _busy,
                canUnlink: canUnlinkAny,
                onLink: _linkGoogle,
                onUnlink: () => _unlinkProvider(_google),
              ),
              _providerTile(
                title: 'Apple',
                linked: providerIds.contains(_apple),
                busy: _busy,
                canUnlink: canUnlinkAny,
                onLink: null,
                onUnlink: () => _unlinkProvider(_apple),
                subtitle: 'Apple 연결은 추후 추가 예정입니다.',
              ),
              _providerTile(
                title: 'Phone',
                linked: providerIds.contains(_phone),
                busy: _busy,
                canUnlink: canUnlinkAny,
                onLink: null,
                onUnlink: () => _unlinkProvider(_phone),
                subtitle: _isPhoneLinkSupported
                    ? '연결 UI는 아래에서 진행하세요.'
                    : '이 플랫폼에서는 Phone 연결이 지원되지 않습니다.',
              ),
              if (!providerIds.contains(_phone) && _isPhoneLinkSupported)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.loginPhoneLabel,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        IntlPhoneField(
                          controller: _phoneController,
                          initialCountryCode: _initialCountryCode(languageCode),
                          disableLengthCheck: true,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: l.loginPhoneLabel,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (phone) {
                            // Extract digits only
                            final digits =
                                phone.number.replaceAll(RegExp(r'[^0-9]'), '');
                            // E.164: remove leading zero if present (e.g., 010 -> 10)
                            final nationalNumber = digits.startsWith('0')
                                ? digits.substring(1)
                                : digits;

                            _completePhoneNumber =
                                '${phone.countryCode}$nationalNumber';

                            // Basic validation: set true if we have some digits
                            // Let the backend/Firebase handle detailed validation
                            _phoneValid = nationalNumber.length >= 7;
                          },
                          onCountryChanged: (_) {
                            _completePhoneNumber = '';
                            _phoneValid = false;
                          },
                          invalidNumberMessage: l.loginPhoneError,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _busy ? null : _sendPhoneCode,
                          child: Text(l.loginSendSms),
                        ),
                        if (_phoneCodeSent) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _smsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l.loginOtpLabel,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _busy ? null : _verifyPhoneCode,
                            child: Text(l.loginVerify),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '기본 로그인 수단',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: linkedProviders.contains(preferred)
                            ? preferred
                            : (linkedProviders.isNotEmpty ? linkedProviders.first : null),
                        items: linkedProviders
                            .map(
                              (p) => DropdownMenuItem<String>(
                                value: p,
                                child: Text(_label(p)),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value == null) return;
                                _setPreferred(value);
                              },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _providerTile({
    required String title,
    required bool linked,
    required bool busy,
    required bool canUnlink,
    required VoidCallback? onLink,
    required VoidCallback onUnlink,
    String? subtitle,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          subtitle ?? (linked ? '연결됨' : '미연결'),
        ),
        trailing: linked
            ? TextButton(
                onPressed: (busy || !canUnlink) ? null : onUnlink,
                child: const Text('해제'),
              )
            : TextButton(
                onPressed: (busy || onLink == null) ? null : onLink,
                child: const Text('연결'),
              ),
      ),
    );
  }
}
