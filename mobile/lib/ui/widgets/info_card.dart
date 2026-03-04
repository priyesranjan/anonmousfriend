import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class InfoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final BorderRadius? borderRadius;
  final Gradient? gradient;

  const InfoCard({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.border,
    this.boxShadow,
    this.borderRadius,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        gradient: gradient,
        border: border,
        boxShadow: boxShadow,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.card),
      ),
      child: child,
    );
  }
}
