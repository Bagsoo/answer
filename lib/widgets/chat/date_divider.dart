import 'package:flutter/material.dart';

class DateDivider extends StatelessWidget {
  final DateTime date;
  final ColorScheme colorScheme;

  const DateDivider({super.key, required this.date, required this.colorScheme});

  String _format(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[dt.weekday - 1];
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 $wd요일';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: colorScheme.onSurface.withOpacity(0.15)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _format(date),
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          Expanded(
            child: Divider(color: colorScheme.onSurface.withOpacity(0.15)),
          ),
        ],
      ),
    );
  }
}
