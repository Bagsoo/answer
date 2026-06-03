import 'package:flutter/material.dart';

class RecentLoginBadge extends StatelessWidget {
  final String text;

  const RecentLoginBadge({super.key, this.text = '최근 사용'});

  @override
  Widget build(BuildContext context) {
    const Color roseGold = Color(0xFFB76E79);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: roseGold.withValues(alpha: 0.1),
        border: Border.all(color: roseGold),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: roseGold,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
