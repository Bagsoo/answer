import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class GroupQrScannerScreen extends StatefulWidget {
  const GroupQrScannerScreen({super.key});

  @override
  State<GroupQrScannerScreen> createState() => _GroupQrScannerScreenState();
}

class _GroupQrScannerScreenState extends State<GroupQrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          if (capture.barcodes.isEmpty) return;
          final code = capture.barcodes.first.rawValue;
          if (code == null || code.isEmpty) return;
          _handled = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}
