import 'dart:async';

import 'package:fints/fints.dart' as fints;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connectors/fints_connector.dart';
import '../nav_key.dart';

/// Dialog-basierte Umsetzung der FinTS-Rückfragen.
class DialogPrompts implements FintsPrompts {
  BuildContext? get _ctx => rootNavigatorKey.currentContext;

  @override
  Future<fints.TanAnswer> tan(fints.TanChallenge challenge) async {
    final ctx = _ctx;
    if (ctx == null || !ctx.mounted) return fints.TanAnswer.cancelled;
    if (challenge.isDecoupled) {
      final r = await showDialog<fints.TanAnswer>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _DecoupledDialog(challenge: challenge),
      );
      return r ?? fints.TanAnswer.cancelled;
    }
    final tan = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _TanDialog(challenge: challenge),
    );
    return (tan == null || tan.trim().isEmpty) ? fints.TanAnswer.cancelled : fints.TanAnswer.tan(tan.trim());
  }

  @override
  Future<fints.TanMethod?> tanMethod(List<fints.TanMethod> methods) async {
    final ctx = _ctx;
    if (ctx == null || !ctx.mounted || methods.isEmpty) return methods.firstOrNull;
    if (methods.length == 1) return methods.first;
    return showDialog<fints.TanMethod>(
      context: ctx,
      builder: (c) => SimpleDialog(
        title: const Text('TAN-Verfahren wählen'),
        children: [
          for (final m in methods)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(m.name)),
            ),
        ],
      ),
    );
  }

  @override
  Future<fints.TanMedium?> tanMedium(List<fints.TanMedium> media) async {
    final ctx = _ctx;
    if (ctx == null || !ctx.mounted || media.isEmpty) return media.firstOrNull;
    if (media.length == 1) return media.first;
    return showDialog<fints.TanMedium>(
      context: ctx,
      builder: (c) => SimpleDialog(
        title: const Text('Gerät / TAN-Medium wählen'),
        children: [
          for (final m in media)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(m.name ?? m.mobileNumberMasked ?? m.mobileNumber ?? m.cardNumber ?? m.mediumClass),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void bankMessage(String subject, String text) {
    final ctx = _ctx;
    if (ctx == null || !ctx.mounted) return;
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(subject.isEmpty ? 'Nachricht deiner Bank' : subject),
        content: SingleChildScrollView(child: Text(text)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }
}

class _DecoupledDialog extends StatefulWidget {
  final fints.TanChallenge challenge;
  const _DecoupledDialog({required this.challenge});

  @override
  State<_DecoupledDialog> createState() => _DecoupledDialogState();
}

class _DecoupledDialogState extends State<_DecoupledDialog> {
  @override
  void initState() {
    super.initState();
    // Die Bibliothek fragt den Freigabestatus selbst ab und meldet die Erledigung.
    widget.challenge.resolved?.then((_) {
      if (mounted) Navigator.of(context).pop(fints.TanAnswer.approved);
    }, onError: (_) {
      if (mounted) Navigator.of(context).pop(fints.TanAnswer.cancelled);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    return AlertDialog(
      title: const Text('Freigabe in der Banking-App'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.plainMessage ?? 'Bitte bestätige den Zugriff in der App deiner Bank (${c.method.name}).'),
        const SizedBox(height: 16),
        if (c.resolved != null) const LinearProgressIndicator(),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, fints.TanAnswer.cancelled), child: const Text('Abbrechen')),
        if (c.manualConfirmation)
          FilledButton(onPressed: () => Navigator.pop(context, fints.TanAnswer.approved), child: const Text('Ich habe freigegeben')),
      ],
    );
  }
}

class _TanDialog extends StatefulWidget {
  final fints.TanChallenge challenge;
  const _TanDialog({required this.challenge});

  @override
  State<_TanDialog> createState() => _TanDialogState();
}

class _TanDialogState extends State<_TanDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('TAN eingeben${c.attempt > 1 ? ' (Versuch ${c.attempt})' : ''}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.plainMessage ?? 'Bitte TAN für ${c.method.name} eingeben.'),
          if (c.image != null) ...[
            const SizedBox(height: 12),
            Center(child: Image.memory(c.image!.bytes, width: 220, gaplessPlayback: true)),
          ],
          if (c.flickerCode != null && c.image == null) ...[
            const SizedBox(height: 12),
            Text(
              'chipTAN mit Flickergrafik wird noch nicht angezeigt. Nutze am besten ein App-Verfahren (pushTAN, SecureGo, photoTAN) '
              'oder chipTAN manuell/QR.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: c.method.numericTan ? TextInputType.number : TextInputType.text,
            inputFormatters: [
              if (c.method.numericTan) FilteringTextInputFormatter.digitsOnly,
              if (c.method.maxTanLength != null) LengthLimitingTextInputFormatter(c.method.maxTanLength),
            ],
            decoration: InputDecoration(labelText: c.method.returnValueText ?? 'TAN'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Senden')),
      ],
    );
  }
}
