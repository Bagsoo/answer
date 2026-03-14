import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedLocale = 'ko_KR';
  String _selectedTimezone = 'Asia/Seoul';
  bool _isLoading = false;

  void _register() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authService = context.read<AuthService>();
    final success = await authService.registerUser(
      name: name,
      locale: _selectedLocale,
      timezone: _selectedTimezone,
    );

    if (!success) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration failed.')),
        );
      }
    }
    // AuthWrapper handles successful navigation when isRegisteredUser becomes true
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Profile')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Please provide your details to finish signing up.'),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLocale,
              decoration: const InputDecoration(
                labelText: 'Language / Locale',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
              items: const [
                DropdownMenuItem(value: 'ko_KR', child: Text('Korean (ko_KR)')),
                DropdownMenuItem(value: 'en_US', child: Text('English (en_US)')),
                DropdownMenuItem(value: 'ja_JP', child: Text('Japanese (ja_JP)')),
              ],
              onChanged: (val) => setState(() => _selectedLocale = val!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedTimezone,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.access_time),
              ),
              items: const [
                DropdownMenuItem(value: 'Asia/Seoul', child: Text('Asia/Seoul')),
                DropdownMenuItem(value: 'America/New_York', child: Text('America/New_York')),
                DropdownMenuItem(value: 'Europe/London', child: Text('Europe/London')),
              ],
              onChanged: (val) => setState(() => _selectedTimezone = val!),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Complete Registration', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
