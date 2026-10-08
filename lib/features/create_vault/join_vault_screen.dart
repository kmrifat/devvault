import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/join_vault.dart';
import '../../shared/desktop_ui.dart' show DesktopTheme;
import '../../shared/ui.dart';
import '../../core/pairing.dart';
import '../../data/providers.dart';
import '../pairing/scan_pairing_code.dart';
import '../settings/storage_form.dart';
import 'desktop_join_vault_view.dart';
import 'setup_layout.dart';

/// Joins a vault that already syncs to a bucket (P2-10): enter the
/// storage, pick the vault found there, type its master password. The
/// password is checked against `vault.json` before anything is downloaded.
///
/// A pairing code (P4-06) fills in the storage instead: scan the QR from
/// the other device (or paste its text) and type the 8-character code.
class JoinVaultScreen extends ConsumerStatefulWidget {
  const JoinVaultScreen({super.key});

  @override
  ConsumerState<JoinVaultScreen> createState() => _JoinVaultScreenState();
}

class _JoinVaultScreenState extends ConsumerState<JoinVaultScreen> {
  final _form = StorageFormModel();
  final _password = TextEditingController();
  final _pairText = TextEditingController();
  final _pairCode = TextEditingController();
  String? _pairError;

  /// The vault a pairing code was for, picked once it's found.
  String? _pairedVaultId;

  List<RemoteVault>? _found;
  String? _foundFor;
  RemoteVault? _chosen;
  bool _busy = false;
  String? _error;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _form.addListener(_changed);
  }

  @override
  void dispose() {
    _form
      ..removeListener(_changed)
      ..dispose();
    _password
      ..clear()
      ..dispose();
    _pairText
      ..clear()
      ..dispose();
    _pairCode.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Found vaults are only valid for the storage they were found in.
  bool get _foundIsCurrent => _found != null && _foundFor == _form.fingerprint;

  Future<void> _find() async {
    setState(() {
      _error = null;
      _found = null;
      _chosen = null;
    });
    if (!_form.validate()) return;
    setState(() => _busy = true);
    final fingerprint = _form.fingerprint;
    try {
      final vaults = await ref
          .read(vaultJoinerProvider)
          .find(_form.settings, _form.credentials);
      if (!mounted) return;
      setState(() {
        _found = vaults;
        _foundFor = fingerprint;
        _chosen = vaults.length == 1
            ? vaults.single
            : vaults.where((v) => v.id == _pairedVaultId).firstOrNull;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = storageErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final text = await scanPairingCode(context);
    if (text != null && mounted) setState(() => _pairText.text = text);
  }

  /// Opens the pairing payload with the code, fills the storage form from
  /// it and looks for the vault straight away.
  Future<void> _usePairing() async {
    setState(() => _pairError = null);
    if (_pairText.text.trim().isEmpty) {
      setState(() => _pairError = 'Scan the QR code or paste the pairing text');
      return;
    }
    setState(() => _busy = true);
    try {
      final contents = await Pairing.open(
        crypto: ref.read(cryptoProvider),
        text: _pairText.text,
        code: _pairCode.text,
        now: ref.read(clockProvider)(),
      );
      if (!mounted) return;
      _form.fill(contents.settings, contents.credentials);
      _pairedVaultId = contents.vaultId;
      _pairText.clear();
      _pairCode.clear();
      setState(() => _busy = false);
      await _find();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pairError = switch (e) {
          PairingFormatException() ||
          PairingExpired() ||
          WrongPairingCode() => e.toString(),
          _ => "Couldn't read the pairing code.",
        };
      });
    }
  }

  Future<void> _join() async {
    final chosen = _chosen;
    if (chosen == null || _busy || !_foundIsCurrent) return;
    if (_password.text.isEmpty) {
      setState(() => _passwordError = 'Enter the master password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _passwordError = null;
    });
    try {
      await ref
          .read(vaultJoinerProvider)
          .join(
            settings: _form.settings,
            credentials: _form.credentials,
            vault: chosen,
            password: _password.text,
          );
      // The vault is open: the router moves on.
    } on WrongPassword {
      if (mounted) {
        setState(
          () => _passwordError = "That password doesn't open this vault",
        );
      }
    } on StorageException catch (e) {
      if (mounted) setState(() => _error = storageErrorMessage(e));
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't join the vault. Nothing was kept on this "
              'device.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final found = _foundIsCurrent ? _found! : null;
    if (DesktopTheme.maybeOf(context) != null) {
      return DesktopJoinVaultView(
        form: _form,
        canScan: canScanPairingCode,
        pairText: _pairText,
        pairCode: _pairCode,
        pairError: _pairError,
        found: found,
        chosen: _chosen,
        password: _password,
        passwordError: _passwordError,
        error: _error,
        busy: _busy,
        onScan: _scan,
        onUsePairing: _usePairing,
        onFind: _find,
        onChoose: (id) =>
            setState(() => _chosen = found!.firstWhere((v) => v.id == id)),
        onJoin: _join,
        onCreate: () => context.go(Routes.create),
      );
    }
    return SetupLayout(
      step: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BCText('Join your vault', type: BCTextType.h2),
          const SizedBox(height: BCSpacing.sm),
          const BCText(
            'Open the vault you already use on another device, from the '
            'bucket it syncs to. You need the same storage keys and the '
            'master password.',
            color: BCTextColor.muted,
          ),
          const StorageSection('With a pairing code'),
          BCCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: BCSpacing.md,
              children: [
                const BCText(
                  'On your other device: Settings › Pair a device. It shows '
                  'a QR code and an 8-character code that work for ten '
                  'minutes.',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
                if (canScanPairingCode)
                  BCButton(
                    variant: BCButtonVariant.secondary,
                    isDisabled: _busy,
                    onPressed: _scan,
                    startContent: const Icon(LucideIcons.scanQrCode, size: 16),
                    child: Text(
                      _pairText.text.isEmpty
                          ? 'Scan QR code'
                          : 'QR code scanned',
                    ),
                  )
                else
                  BCTextField(
                    key: const ValueKey('pairing-text'),
                    children: [
                      const BCTextFieldLabel('Pairing text'),
                      BCTextFieldInput(
                        controller: _pairText,
                        hintText: 'devvault-pair:1:…',
                      ),
                      const BCTextFieldDescription(
                        'From “Copy pairing text” on the other device',
                      ),
                    ],
                  ),
                BCTextField(
                  key: const ValueKey('pairing-code'),
                  isInvalid: _pairError != null,
                  children: [
                    const BCTextFieldLabel('Code'),
                    BCTextFieldInput(
                      controller: _pairCode,
                      hintText: 'ABCD-EFGH',
                      onSubmitted: (_) => _usePairing(),
                    ),
                    if (_pairError case final error?) BCTextFieldError(error),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: BCButton(
                    isDisabled: _busy,
                    onPressed: _usePairing,
                    child: const Text('Use pairing code'),
                  ),
                ),
              ],
            ),
          ),
          const StorageSection('Or enter the storage yourself'),
          StorageFormView(model: _form),
          const SizedBox(height: BCSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BCButton(
              variant: BCButtonVariant.secondary,
              isDisabled: _busy,
              onPressed: _find,
              startContent: _busy && found == null
                  ? const BCSpinner(size: BCSpinnerSize.sm)
                  : const Icon(LucideIcons.search, size: 16),
              child: const Text('Find vaults'),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: BCSpacing.md),
            StorageResult(
              icon: LucideIcons.circleAlert,
              tint: bc.danger,
              title: 'Couldn’t continue',
              lines: [error],
            ),
          ],
          if (found != null) ...[
            const StorageSection('Vaults in this bucket'),
            if (found.isEmpty)
              StorageResult(
                icon: LucideIcons.searchX,
                tint: bc.muted,
                title: 'No vault here yet',
                lines: const [
                  'Check the folder, or set up sync from the device that '
                      'has the vault.',
                ],
              )
            else
              BCCard(
                child: BCRadioGroup<String>(
                  value: _chosen?.id,
                  onValueChange: (id) => setState(
                    () => _chosen = found.firstWhere((v) => v.id == id),
                  ),
                  children: [
                    for (final v in found)
                      BCRadio(
                        value: v.id,
                        label: 'Vault ${v.id.substring(0, 8)}',
                        description:
                            'Created ${DateFormat.yMMMd().format(v.header.createdAt.toLocal())} · '
                            '${v.id}',
                      ),
                  ],
                ),
              ),
            if (_chosen != null) ...[
              const SizedBox(height: BCSpacing.lg),
              PasswordField(
                label: 'Master password',
                controller: _password,
                autofocus: true,
                isDisabled: _busy,
                error: _passwordError,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: BCSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: BCButton(
                  isDisabled: _busy,
                  onPressed: _join,
                  startContent: _busy
                      ? const BCSpinner(size: BCSpinnerSize.sm)
                      : null,
                  child: Text(_busy ? 'Joining…' : 'Join vault'),
                ),
              ),
            ],
          ],
          const SizedBox(height: BCSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: BCLinkButton(
              onPressed: _busy ? null : () => context.go(Routes.create),
              child: const Text('Create a new vault instead'),
            ),
          ),
        ],
      ),
    );
  }
}
