import 'package:flutter/material.dart';

// ── 첨부 아이템 모델 ──────────────────────────────────────────────────────────
class AttachItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  
  AttachItem({
    required this.icon, 
    required this.label, 
    required this.color, 
    required this.onTap
  });
}

// ── 첨부 버튼 위젯 ────────────────────────────────────────────────────────────
class AttachButton extends StatelessWidget {
  final AttachItem item;
  final ColorScheme colorScheme;

  const AttachButton({super.key, required this.item, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: item.color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
