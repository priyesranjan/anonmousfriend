import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final EdgeInsetsGeometry padding;
  final int maxLines;
  final bool fullWidth;
  final double fontSize;

  const StatusChip({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.maxLines = 1,
    this.fullWidth = true,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
