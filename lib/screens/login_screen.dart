import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;
  String _errorMessage = '';

  void _sendSms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // Provide a valid format with country code (e.g., +821012345678)
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() {
        _errorMessage = 'Please enter a valid number with country code (e.g. +82...)';
        _isLoading = false;
      });
      return;
    }

    await context.read<AuthService>().verifyPhoneNumber(
      phone,
      (error) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      },
      () {
        setState(() {
          _codeSent = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP Code sent!')),
        );
      },
    );
  }

  void _verifyOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final otp = _otpController.text.trim();
    final authService = context.read<AuthService>();
    final success = await authService.verifyOTP(otp);

    if (!success) {
      setState(() {
        _errorMessage = 'Invalid OTP Code.';
        _isLoading = false;
      });
    }
    // If successful, AuthWrapper will handle the navigation!
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Login')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.chat_bubble_rounded, size: 80, color: Colors.amber),
            const SizedBox(height: 32),
            if (!_codeSent) ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+82 10 1234 5678',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _sendSms,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Send SMS', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '6-Digit OTP',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Verify & Login', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
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
          ],
        ),
      ),
    );
  }
}
