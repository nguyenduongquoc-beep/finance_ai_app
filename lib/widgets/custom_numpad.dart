import 'package:flutter/material.dart';
import '../utils/formatters.dart';

/// Bottom-sheet numpad for entering currency amounts.
/// Returns the formatted string when confirmed, or null if dismissed.
class CustomNumpad extends StatefulWidget {
  final String initialValue;

  const CustomNumpad({super.key, this.initialValue = ''});

  @override
  State<CustomNumpad> createState() => _CustomNumpadState();
}

class _CustomNumpadState extends State<CustomNumpad> {
  late String _raw; // digits only, no separators

  @override
  void initState() {
    super.initState();
    // Strip non-digit characters from initialValue
    _raw = AppFormatters.parseCurrencyInput(widget.initialValue)
        .toStringAsFixed(0)
        .replaceAll(RegExp(r'\.0$'), '');
    if (_raw == '0') _raw = '';
  }

  String get _display {
    if (_raw.isEmpty) return '0';
    final value = double.tryParse(_raw) ?? 0;
    return AppFormatters.number(value);
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'DEL') {
        if (_raw.isNotEmpty) _raw = _raw.substring(0, _raw.length - 1);
      } else if (key == '00') {
        if (_raw.isNotEmpty) _raw += '00';
      } else {
        if (_raw == '0') {
          _raw = key;
        } else {
          _raw += key;
        }
      }
      // Guard: max 15 digits
      if (_raw.length > 15) _raw = _raw.substring(0, 15);
    });
  }

  void _confirm() {
    final value = double.tryParse(_raw) ?? 0;
    if (value <= 0) {
      Navigator.of(context).pop<String>(null);
      return;
    }
    Navigator.of(context).pop<String>(AppFormatters.number(value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Display
            Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_display đ',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Numpad grid
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.0,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                ...[
                  '1', '2', '3',
                  '4', '5', '6',
                  '7', '8', '9',
                  '00', '0', 'DEL',
                ].map((key) => _NumpadKey(
                      label: key,
                      isDel: key == 'DEL',
                      onTap: () => _onKey(key),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _confirm,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Xác nhận',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumpadKey extends StatelessWidget {
  final String label;
  final bool isDel;
  final VoidCallback onTap;

  const _NumpadKey(
      {required this.label, required this.onTap, this.isDel = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isDel
          ? theme.colorScheme.errorContainer.withOpacity(0.6)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: isDel
              ? Icon(Icons.backspace_outlined,
                  color: theme.colorScheme.error, size: 22)
              : Text(
                  label,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
        ),
      ),
    );
  }
}
