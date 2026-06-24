import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_radius.dart';
import 'package:altcast/core/theme/app_spacing.dart';

class GlassSheetDropdown<T> extends StatelessWidget {
  const GlassSheetDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassSheetFieldFrame(
      label: label,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          dropdownColor: AppColors.surfaceElevated.withValues(alpha: 0.96),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
            size: 24,
          ),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class GlassSheetTextField extends StatelessWidget {
  const GlassSheetTextField({
    required this.label,
    this.controller,
    this.initialValue,
    this.keyboardType,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassSheetFieldFrame(
      label: label,
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        keyboardType: keyboardType,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        cursorColor: AppColors.primary,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isCollapsed: true,
          counterText: '',
          hintText: label,
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _GlassSheetFieldFrame extends StatelessWidget {
  const _GlassSheetFieldFrame({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: 7),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
                spreadRadius: -10,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 15,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
