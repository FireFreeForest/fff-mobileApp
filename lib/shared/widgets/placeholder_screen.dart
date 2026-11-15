import 'package:flutter/material.dart';

import 'app_header.dart';
import 'empty_state.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.message,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(title: title, subtitle: subtitle, actions: actions),
          Expanded(
            child: EmptyState(icon: icon, title: title, message: message),
          ),
        ],
      ),
    );
  }
}
