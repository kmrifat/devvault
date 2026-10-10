import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../data/updates.dart';
import '../../services/updates.dart';
import '../../shared/desktop_ui.dart';

/// "Published 12 Oct 2026.", or nothing when GitHub didn't say.
String? publishedOn(Release release) => switch (release.publishedAt) {
  final at? => 'Published ${DateFormat('d MMM y').format(at.toLocal())}.',
  null => null,
};

/// What Settings says about the checks, a line each: facts only, and
/// never "latest" after a failure (ADR-0007 §2).
List<String> updateStatusLines(UpdateStatus status, AppVersion running) {
  final time = DateFormat("d MMM y 'at' HH:mm");
  final checked = status.checkedAt;
  final failed = status.failedAt;
  final available = status.availableFor(running);
  return [
    if (status.checking) 'Checking…',
    if (available != null)
      [
        'DevVault ${available.version} is available.',
        ?publishedOn(available),
      ].join(' '),
    if (checked != null)
      available != null || failed != null
          ? 'Last checked ${time.format(checked.toLocal())}.'
          : 'Last checked ${time.format(checked.toLocal())}: $running is '
                'the latest release.',
    if (failed != null)
      'Couldn’t check on ${time.format(failed.toLocal())}. '
              '${status.failure ?? ''}'
          .trim(),
    if (!status.checking && checked == null && failed == null)
      'Not checked yet.',
  ];
}

/// Hands [release] to the OS's updater; says so in a toast if it can't
/// start. From there the updater shows its own window.
Future<void> startUpdate(
  BuildContext context,
  UpdateInstaller installer,
  Release release,
) async {
  try {
    await installer.install(release);
  } on UpdateCheckFailed catch (e) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      title: 'Couldn’t start the update',
      message: e.reason,
      kind: DesktopToastKind.danger,
    );
  }
}

/// Under the toolbar of the desktop window (N03): first the one-time
/// question whether to check for updates, then, when a newer release is
/// out, a line saying so. Nothing on phones or where the version is
/// unknown.
class UpdateStrip extends ConsumerWidget {
  const UpdateStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(appVersionProvider);
    if (running == null) return const SizedBox.shrink();
    final checks = ref.watch(settingsProvider.select((s) => s.updateChecks));
    final settings = ref.read(settingsProvider.notifier);
    if (checks == null) {
      return _Strip(
        text:
            'Check GitHub for new versions of DevVault once a day? Only that '
            'request is sent: no version, device or vault.',
        actions: [
          DesktopButton(
            label: 'Not Now',
            onPressed: () => settings.setUpdateChecks(false),
          ),
          DesktopButton(
            label: 'Check Daily',
            kind: DesktopButtonKind.primary,
            onPressed: () => settings.setUpdateChecks(true),
          ),
        ],
      );
    }
    final status = ref.watch(updatesProvider);
    final release = status.availableFor(running);
    if (release == null || status.dismissed == release.version) {
      return const SizedBox.shrink();
    }
    final installer = ref.watch(updateInstallerProvider);
    return _Strip(
      text: [
        'DevVault ${release.version} is available.',
        ?publishedOn(release),
      ].join(' '),
      actions: [
        DesktopButton(
          label: 'Later',
          onPressed: () =>
              ref.read(updatesProvider.notifier).dismiss(release.version),
        ),
        DesktopButton(
          label: 'View Release',
          kind: installer == null
              ? DesktopButtonKind.primary
              : DesktopButtonKind.plain,
          onPressed: () => ref.read(linkOpenerProvider).open(release.page),
        ),
        if (installer != null)
          DesktopButton(
            label: 'Update…',
            kind: DesktopButtonKind.primary,
            onPressed: () => startUpdate(context, installer, release),
          ),
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.groupBox,
          border: Border(
            bottom: BorderSide(color: colors.separator, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            spacing: 8,
            children: [
              DesktopIcon(
                DesktopSymbol.info,
                size: 14,
                color: colors.accentIcon,
              ),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.text,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
