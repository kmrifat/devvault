import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/join_vault.dart';
import '../../shared/ui.dart';
import '../settings/storage_form.dart';
import 'setup_layout.dart';

/// Joins a vault that already syncs to a bucket (P2-10): enter the
/// storage, pick the vault found there, type its master password. The
/// password is checked against `vault.json` before anything is downloaded.
class JoinVaultScreen extends ConsumerStatefulWidget {
  const JoinVaultScreen({super.key});

  @override
  ConsumerState<JoinVaultScreen> createState() => _JoinVaultScreenState();
}

class _JoinVaultScreenState extends ConsumerState<JoinVaultScreen> {
  final _form = StorageFormModel();
  final _password = TextEditingController();

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
        _chosen = vaults.length == 1 ? vaults.single : null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = storageErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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
