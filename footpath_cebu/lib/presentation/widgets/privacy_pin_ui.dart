import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared, responsive presentation primitives for privacy-PIN flows.
///
/// Keeping setup, unlock, and management visually consistent helps users
/// recognise that each screen belongs to the same profile-security feature.
class PrivacyPinPanel extends StatelessWidget {
  const PrivacyPinPanel({super.key, required this.child, this.maxWidth = 560});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 600;
        final horizontalPadding = isTablet ? 32.0 : 16.0;
        final cardPadding = isTablet ? 36.0 : 22.0;

        return SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isTablet ? 32 : 20,
              horizontalPadding,
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(cardPadding),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrivacyPinHeader extends StatelessWidget {
  const PrivacyPinHeader({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.shield_outlined,
    this.badgeLabel = 'PROFILE SECURITY',
  });

  final String title;
  final String description;
  final IconData icon;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(icon, size: 34, color: colors.onPrimaryContainer),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            badgeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class PrivacyPinField extends StatefulWidget {
  const PrivacyPinField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PrivacyPinField> createState() => _PrivacyPinFieldState();
}

class _PrivacyPinFieldState extends State<PrivacyPinField> {
  bool _obscurePin = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: _obscurePin,
      obscuringCharacter: '●',
      keyboardType: TextInputType.number,
      textInputAction: widget.textInputAction,
      maxLength: 6,
      enableSuggestions: false,
      autocorrect: false,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: '4–6 digits',
        errorText: widget.errorText,
        counterText: '',
        filled: true,
        prefixIcon: const Icon(Icons.dialpad_outlined),
        suffixIcon: IconButton(
          tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
          onPressed: widget.enabled
              ? () => setState(() => _obscurePin = !_obscurePin)
              : null,
          icon: Icon(
            _obscurePin
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

class PrivacyPinGuidance extends StatelessWidget {
  const PrivacyPinGuidance({super.key, this.isChange = false});

  final bool isChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: colors.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isChange
                  ? 'Use 4–6 digits. Choose a PIN that is different from your current PIN.'
                  : 'Use 4–6 digits that your household can remember. Avoid birthdays and simple patterns.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onPrimaryContainer,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacyPinErrorBanner extends StatelessWidget {
  const PrivacyPinErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPinPrimaryButton extends StatelessWidget {
  const PrivacyPinPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(busy ? 'Please wait…' : label),
      ),
    );
  }
}
