import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
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
  verified,
  copy,
  info,
  alert,
  privacy,
  document,
  remove,
  reveal,
  conceal;

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
    verified => CupertinoIcons.checkmark_circle,
    copy => CupertinoIcons.doc_on_doc,
    info => CupertinoIcons.info_circle,
    alert => CupertinoIcons.exclamationmark_circle,
    privacy => CupertinoIcons.checkmark_shield,
    document => CupertinoIcons.doc,
    remove => CupertinoIcons.minus_circle,
    reveal => CupertinoIcons.eye,
    conceal => CupertinoIcons.eye_slash,
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
    verified => fl.FluentIcons.completed,
    copy => fl.FluentIcons.copy,
    info => fl.FluentIcons.info,
    alert => fl.FluentIcons.error,
    privacy => fl.FluentIcons.shield,
    document => fl.FluentIcons.page,
    remove => fl.FluentIcons.remove,
    reveal => fl.FluentIcons.view,
    conceal => fl.FluentIcons.hide,
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
    verified => yaru.YaruIcons.ok,
    copy => yaru.YaruIcons.copy,
    info => yaru.YaruIcons.information,
    alert => yaru.YaruIcons.error,
    privacy => yaru.YaruIcons.shield,
    document => yaru.YaruIcons.document,
    remove => yaru.YaruIcons.minus,
    reveal => yaru.YaruIcons.eye,
    conceal => yaru.YaruIcons.hide,
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
