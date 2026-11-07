import 'package:flutter/material.dart';

import 'design.dart';

class ChatNotice extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onTap;
  const ChatNotice({super.key, required this.text, this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => Center(
    child: InkWell(
      onTap: onTap,
      customBorder: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: context.tone.ink3),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: context.tone.ink3,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
