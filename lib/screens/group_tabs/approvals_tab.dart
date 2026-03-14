import 'package:flutter/material.dart';

class ApprovalsTab extends StatelessWidget {
  final String groupId;

  const ApprovalsTab({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 48, color: Theme.of(context).colorScheme.primary),
          SizedBox(height: 16),
          Text('Approvals & Documents is under construction!'),
        ],
      ),
    );
  }
}