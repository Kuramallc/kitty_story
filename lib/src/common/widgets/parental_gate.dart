import 'dart:math';

import 'package:flutter/material.dart';

/// An "ask a grown-up" gate: a small multiplication question an adult answers
/// quickly but a young child generally can't. Returns `true` if passed, `false`
/// if cancelled. Shown before sensitive actions (recording a voice, publishing
/// to the community) per Apple/Google kids-app guidelines.
Future<bool> showParentalGate(BuildContext context) async {
  final passed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ParentalGateDialog(),
  );
  return passed ?? false;
}

class _ParentalGateDialog extends StatefulWidget {
  const _ParentalGateDialog();

  @override
  State<_ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<_ParentalGateDialog> {
  final _random = Random();
  final _controller = TextEditingController();
  late int _a;
  late int _b;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _newQuestion();
  }

  void _newQuestion() {
    _a = 2 + _random.nextInt(8); // 2..9
    _b = 2 + _random.nextInt(8); // 2..9
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = int.tryParse(_controller.text.trim());
    if (answer == _a * _b) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _wrong = true;
        _controller.clear();
        _newQuestion();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Ask a grown-up'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('To continue, please solve:'),
          const SizedBox(height: 12),
          Text('$_a × $_b = ?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Answer',
              errorText: _wrong ? 'Not quite — try again.' : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
