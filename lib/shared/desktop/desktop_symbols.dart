import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yaru/yaru.dart' as yaru;

import 'desktop_theme.dart';

/// The icons desktop screens use, by meaning. Each OS draws them from its
/// own set (ADR-0005): SF-style Cupertino icons on macOS, Fluent icons on
/// Windows, Yaru icons on Linux.
enum DesktopSymbol {
  allItems,
  expiring,
  expired,
  conflicts,
  unreadable,
  add,
  importFile,
  tag,
  settings,
  timer,
  lock,
  search,
  synced,
  syncing,
  syncOff,
  syncFailed,
  keyChanged,
  chevronRight,
  chevronDown,
  platformApple,
  platformAndroid,
  platformWeb,
  platformServer,
  platformDesktop,
  platformOther,

  // Lock screens (N00–N02).
  fingerprint,
  faceId,
  submit,
  keyDerivation,
  encrypted,
  savePdf,
  saveText,
  printer,
  copy;

  IconData of(DesktopKit kit) => switch (kit) {
    DesktopKit.macos => _macos,
    DesktopKit.fluent => _fluent,
    DesktopKit.yaru => _yaru,
  };

  IconData get _macos => switch (this) {
    allItems => CupertinoIcons.square_stack_3d_up,
    expiring => CupertinoIcons.clock,
    expired => CupertinoIcons.xmark_circle,
    conflicts => CupertinoIcons.arrow_merge,
    unreadable => CupertinoIcons.exclamationmark_shield,
    add => CupertinoIcons.plus,
    importFile => CupertinoIcons.tray_arrow_down,
    tag => CupertinoIcons.tag,
    settings => CupertinoIcons.gear,
    timer => CupertinoIcons.timer,
    lock => CupertinoIcons.lock,
    search => CupertinoIcons.search,
    synced => CupertinoIcons.cloud,
    syncing => CupertinoIcons.arrow_2_circlepath,
    syncOff => CupertinoIcons.wifi_slash,
    syncFailed => CupertinoIcons.exclamationmark_triangle,
    keyChanged => CupertinoIcons.lock_rotation,
    chevronRight => CupertinoIcons.chevron_right,
    chevronDown => CupertinoIcons.chevron_down,
    platformApple => CupertinoIcons.device_phone_portrait,
    platformAndroid => CupertinoIcons.device_phone_portrait,
    platformWeb => CupertinoIcons.globe,
    platformServer => CupertinoIcons.cube_box,
    platformDesktop => CupertinoIcons.desktopcomputer,
    platformOther => CupertinoIcons.cube,
    // CupertinoIcons has no Touch ID or Face ID glyph; the app's own
    // Lucide set stands in for them.
    fingerprint => LucideIcons.fingerprint,
    faceId => LucideIcons.scanFace,
    submit => CupertinoIcons.arrow_right_circle_fill,
    keyDerivation => CupertinoIcons.lock_shield,
    encrypted => CupertinoIcons.checkmark_shield,
    savePdf => CupertinoIcons.arrow_down_doc,
    saveText => CupertinoIcons.doc_text,
    printer => CupertinoIcons.printer,
    copy => CupertinoIcons.doc_on_doc,
  };

  IconData get _fluent => switch (this) {
    allItems => fl.FluentIcons.stack,
    expiring => fl.FluentIcons.clock,
    expired => fl.FluentIcons.error_badge,
    conflicts => fl.FluentIcons.branch_merge,
    unreadable => fl.FluentIcons.shield_alert,
    add => fl.FluentIcons.add,
    importFile => fl.FluentIcons.download,
    tag => fl.FluentIcons.tag,
    settings => fl.FluentIcons.settings,
    timer => fl.FluentIcons.timer,
    lock => fl.FluentIcons.lock,
    search => fl.FluentIcons.search,
    synced => fl.FluentIcons.cloud,
    syncing => fl.FluentIcons.sync,
    syncOff => fl.FluentIcons.cloud_not_synced,
    syncFailed => fl.FluentIcons.warning,
    keyChanged => fl.FluentIcons.permissions,
    chevronRight => fl.FluentIcons.chevron_right,
    chevronDown => fl.FluentIcons.chevron_down,
    platformApple => fl.FluentIcons.cell_phone,
    platformAndroid => fl.FluentIcons.cell_phone,
    platformWeb => fl.FluentIcons.globe,
    platformServer => fl.FluentIcons.server,
    platformDesktop => fl.FluentIcons.t_v_monitor,
    platformOther => fl.FluentIcons.package,
    fingerprint => fl.FluentIcons.fingerprint,
    faceId => fl.FluentIcons.contact,
    submit => fl.FluentIcons.forward,
    keyDerivation => fl.FluentIcons.processing,
    encrypted => fl.FluentIcons.shield,
    savePdf => fl.FluentIcons.pdf,
    saveText => fl.FluentIcons.page,
    printer => fl.FluentIcons.print,
    copy => fl.FluentIcons.copy,
  };

  IconData get _yaru => switch (this) {
    allItems => yaru.YaruIcons.app_grid,
    expiring => yaru.YaruIcons.clock,
    expired => yaru.YaruIcons.error,
    conflicts => yaru.YaruIcons.important,
    unreadable => yaru.YaruIcons.shield_warning,
    add => yaru.YaruIcons.plus,
    importFile => yaru.YaruIcons.document_open,
    tag => yaru.YaruIcons.tag,
    settings => yaru.YaruIcons.settings,
    timer => yaru.YaruIcons.hourglass,
    lock => yaru.YaruIcons.lock,
    search => yaru.YaruIcons.search,
    synced => yaru.YaruIcons.cloud,
    syncing => yaru.YaruIcons.sync,
    syncOff => yaru.YaruIcons.network_offline,
    syncFailed => yaru.YaruIcons.sync_error,
    keyChanged => yaru.YaruIcons.key,
    chevronRight => yaru.YaruIcons.pan_end,
    chevronDown => yaru.YaruIcons.pan_down,
    platformApple => yaru.YaruIcons.apple,
    platformAndroid => yaru.YaruIcons.smartphone,
    platformWeb => yaru.YaruIcons.globe,
    platformServer => yaru.YaruIcons.server,
    platformDesktop => yaru.YaruIcons.computer,
    platformOther => yaru.YaruIcons.package,
    fingerprint => yaru.YaruIcons.fingerprint,
    faceId => yaru.YaruIcons.user,
    submit => yaru.YaruIcons.go_next,
    keyDerivation => yaru.YaruIcons.chip,
    encrypted => yaru.YaruIcons.shield,
    savePdf => yaru.YaruIcons.save,
    saveText => yaru.YaruIcons.document,
    printer => yaru.YaruIcons.printer,
    copy => yaru.YaruIcons.copy,
  };
}

/// [symbol] in the current kit's icon set.
class DesktopIcon extends StatelessWidget {
  const DesktopIcon(
    this.symbol, {
    super.key,
    this.size = 16,
    this.color,
    this.semanticLabel,
  });

  final DesktopSymbol symbol;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Icon(
    symbol.of(context.desktopKit),
    size: size,
    color: color ?? context.desktopColors.secondaryText,
    semanticLabel: semanticLabel,
  );
}
