import '../../data/sync_setup.dart' show StorageProvider;

import '../../shared/desktop_ui.dart';
import 'storage_form.dart' show StorageFormModel;

/// The storage form on desktop (design frame N07b): a classic form in a
/// group box, labels right-aligned, for the [StorageFormModel] that phones
/// edit with `StorageFormView`. A field's problem shows under it in red
/// ([DesktopFormRow.error]).
///
/// [footer] sits under the fields, in the controls' column: the result of
/// the last connection test.
class DesktopStorageForm extends StatelessWidget {
  const DesktopStorageForm({super.key, required this.model, this.footer});

  final StorageFormModel model;
  final Widget? footer;

  static const double labelWidth = 140;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final provider = model.provider;
        final errors = model.errors;
        final usesEndpoint =
            provider == StorageProvider.minio ||
            provider == StorageProvider.custom;
        final footer = this.footer;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.groupBoxInner,
            border: Border.all(color: colors.groupBoxStroke, width: 0.5),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius + 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: DesktopForm(
              labelWidth: labelWidth,
              children: [
                DesktopFormRow(
                  label: 'Storage',
                  child: _Narrow(
                    child: Semantics(
                      label: 'Storage',
                      child: DesktopPopup<StorageProvider>(
                        value: provider,
                        choices: [
                          for (final p in StorageProvider.values)
                            DesktopChoice(p, p.label),
                        ],
                        onChanged: model.setProvider,
                      ),
                    ),
                  ),
                ),
                if (provider == StorageProvider.r2)
                  _Field(
                    label: 'Account ID',
                    controller: model.accountId,
                    placeholder: '32 hex characters',
                    error: errors['accountId'],
                    mono: true,
                  ),
                if (usesEndpoint)
                  _Field(
                    label: 'Endpoint',
                    controller: model.endpoint,
                    placeholder: 'https://s3.example.com',
                    error: errors['endpoint'],
                  ),
                if (provider != StorageProvider.r2)
                  _Field(
                    label: 'Region',
                    controller: model.region,
                    placeholder: switch (provider) {
                      StorageProvider.aws => 'eu-west-1',
                      StorageProvider.b2 => 'us-west-004',
                      _ => 'Optional',
                    },
                    error: errors['region'],
                    narrow: true,
                  ),
                _Field(
                  label: 'Bucket',
                  controller: model.bucket,
                  placeholder: 'my-devvault',
                  error: errors['bucket'],
                  narrow: true,
                ),
                _Field(
                  label: 'Folder',
                  controller: model.prefix,
                  placeholder: 'Optional',
                  error: errors['prefix'],
                  narrow: true,
                ),
                if (provider != StorageProvider.r2)
                  DesktopFormRow(
                    label: 'Addressing',
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DesktopCheckbox(
                        value: model.pathStyle,
                        onChanged: model.setPathStyle,
                        label: 'Path-style',
                      ),
                    ),
                  ),
                _Field(
                  label: 'Access key ID',
                  controller: model.accessKey,
                  error: errors['accessKey'],
                  mono: true,
                ),
                _Field(
                  label: 'Secret access key',
                  controller: model.secretKey,
                  error: errors['secretKey'],
                  secret: true,
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: labelWidth + DesktopMetrics.formLabelGap,
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Keeps a short value's control from stretching across the form.
class _Narrow extends StatelessWidget {
  const _Narrow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: SizedBox(width: DesktopMetrics.narrowFieldWidth, child: child),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.placeholder,
    this.error,
    this.mono = false,
    this.secret = false,
    this.narrow = false,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final String? error;
  final bool mono;
  final bool secret;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    Widget field = Semantics(
      label: label,
      child: DesktopTextField(
        controller: controller,
        placeholder: placeholder,
        mono: mono,
        obscureText: secret,
      ),
    );
    if (narrow) field = _Narrow(child: field);
    return DesktopFormRow(label: label, error: error, child: field);
  }
}
