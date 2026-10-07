import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/vault_session.dart';
import '../features/import/import_dialog.dart';
import '../features/import/import_draft.dart';
import '../services/incoming_files.dart';
import 'router.dart';

/// Opens the import dialog (B4) for files other apps hand to DevVault
/// ("Open in", share). Files that arrive while the vault is locked wait
/// until it's unlocked; they never touch the vault before that.
class IncomingImports extends ConsumerStatefulWidget {
  const IncomingImports({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingImports> createState() => _IncomingImportsState();
}

class _IncomingImportsState extends ConsumerState<IncomingImports> {
  final _waiting = <String>[];
  StreamSubscription<void>? _sub;
  late final AppLifecycleListener _lifecycle;
  bool _importing = false;

  IncomingFiles get _incoming => ref.read(incomingFilesProvider);

  @override
  void initState() {
    super.initState();
    _sub = _incoming.available.listen((_) => _collect());
    // A file opened while DevVault was in the background.
    _lifecycle = AppLifecycleListener(onResume: _collect);
    ref.listenManual(vaultSessionProvider, (_, next) {
      if (next is Unlocked) _importWaiting();
    });
    _collect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    final paths = await _incoming.take();
    if (paths.isEmpty || !mounted) return;
    _waiting.addAll(paths);
    await _importWaiting();
  }

  Future<void> _importWaiting() async {
    if (_importing || _waiting.isEmpty) return;
    if (ref.read(vaultSessionProvider) is! Unlocked) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    _importing = true;
    try {
      final paths = [..._waiting];
      _waiting.clear();
      final files = <PickedFile>[
        for (final path in paths)
          if (await readIncoming(path) case final f?)
            PickedFile(name: f.name, bytes: f.bytes),
      ];
      if (files.isNotEmpty && context.mounted) {
        await showImportDialog(context, files: files);
      }
    } finally {
      _importing = false;
    }
    // More may have arrived meanwhile.
    if (_waiting.isNotEmpty) await _importWaiting();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
