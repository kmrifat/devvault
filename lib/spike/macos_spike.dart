// Desktop UI spike: the vault screen in macos_ui (macOS look).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Icons, ThemeMode;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:macos_ui/macos_ui.dart';

import 'spike_data.dart';

class MacosSpikeApp extends StatelessWidget {
  const MacosSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'DevVault',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const _VaultWindow(),
    );
  }
}

class _VaultWindow extends StatefulWidget {
  const _VaultWindow();

  @override
  State<_VaultWindow> createState() => _VaultWindowState();
}

class _VaultWindowState extends State<_VaultWindow> {
  int _section = 0;
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: _menus(),
      child: MacosWindow(
        sidebar: Sidebar(
          minWidth: 200,
          startWidth: 220,
          top: const MacosSearchField(placeholder: 'Search'),
          builder: (context, scrollController) => SidebarItems(
            currentIndex: _section,
            scrollController: scrollController,
            itemSize: SidebarItemSize.small,
            onChanged: (i) => setState(() => _section = i),
            items: const [
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.square_stack_3d_up),
                label: Text('All items'),
                trailing: Text('8'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.clock),
                label: Text('Expiring soon'),
                trailing: Text('2'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.xmark_circle),
                label: Text('Expired'),
                trailing: Text('1'),
              ),
              SidebarItem(section: true, label: Text('Apps')),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.app),
                label: Text('Kitchenly'),
                disclosureItems: [
                  SidebarItem(
                    leading: MacosIcon(CupertinoIcons.device_phone_portrait),
                    label: Text('iOS'),
                  ),
                  SidebarItem(
                    leading: MacosIcon(Icons.android),
                    label: Text('Android'),
                  ),
                ],
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.app),
                label: Text('Ledgerly'),
              ),
            ],
          ),
          bottom: const MacosListTile(
            leading: MacosIcon(CupertinoIcons.gear),
            title: Text('Settings'),
          ),
        ),
        child: MacosScaffold(
          toolBar: ToolBar(
            title: const Text('All items'),
            titleWidth: 150,
            actions: [
              ToolBarIconButton(
                label: 'Import',
                icon: const MacosIcon(CupertinoIcons.doc_on_doc),
                showLabel: false,
                tooltipMessage: 'Import a file (⌘I)',
                onPressed: () {},
              ),
              ToolBarIconButton(
                label: 'New item',
                icon: const MacosIcon(CupertinoIcons.add),
                showLabel: false,
                tooltipMessage: 'New item (⌘N)',
                onPressed: () {},
              ),
              const ToolBarSpacer(),
              ToolBarIconButton(
                label: 'Lock',
                icon: const MacosIcon(CupertinoIcons.lock),
                showLabel: false,
                tooltipMessage: 'Lock (⌘L)',
                onPressed: () {},
              ),
            ],
          ),
          children: [
            ResizablePane(
              minSize: 260,
              startSize: 340,
              maxSize: 480,
              resizableSide: ResizableSide.right,
              builder: (context, scrollController) => _List(
                selected: _selected,
                scrollController: scrollController,
                onSelect: (i) => setState(() => _selected = i),
              ),
            ),
            ContentArea(
              builder: (context, scrollController) => _Inspector(
                item: spikeItems[_selected],
                scrollController: scrollController,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PlatformMenuItem> _menus() => [
    const PlatformMenu(
      label: 'DevVault',
      menus: [
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItem(
          label: 'New Item',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
          onSelected: () {},
        ),
        PlatformMenuItem(
          label: 'Import…',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
          onSelected: () {},
        ),
      ],
    ),
    PlatformMenu(
      label: 'Vault',
      menus: [
        PlatformMenuItem(
          label: 'Sync Now',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
          onSelected: () {},
        ),
        PlatformMenuItem(
          label: 'Lock',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
          onSelected: () {},
        ),
      ],
    ),
  ];
}

/// Table-like rows: name and type, then where it lives and its expiry.
class _List extends StatelessWidget {
  const _List({
    required this.selected,
    required this.scrollController,
    required this.onSelect,
  });

  final int selected;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: spikeItems.length,
      itemBuilder: (context, i) {
        final item = spikeItems[i];
        final isSelected = i == selected;
        final fg = isSelected ? Colors.white : theme.typography.body.color;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? theme.primaryColor : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                MacosIcon(
                  item.file == null ? CupertinoIcons.lock : CupertinoIcons.doc,
                  size: 16,
                  color: fg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.typography.body.copyWith(color: fg),
                      ),
                      Text(
                        '${item.type} · ${item.app}',
                        style: theme.typography.caption1.copyWith(
                          color: isSelected
                              ? Colors.white70
                              : MacosColors.systemGrayColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.expiry case final expiry?)
                  Text(
                    expiry,
                    style: theme.typography.caption1.copyWith(color: fg),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Inspector extends StatefulWidget {
  const _Inspector({required this.item, required this.scrollController});

  final SpikeItem item;
  final ScrollController scrollController;

  @override
  State<_Inspector> createState() => _InspectorState();
}

class _InspectorState extends State<_Inspector> {
  late final _platform = TextEditingController(text: widget.item.platform);
  String _environment = 'production';
  bool _remind = true;

  @override
  void didUpdateWidget(_Inspector old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) {
      _platform.text = widget.item.platform;
      _environment = widget.item.environment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final item = widget.item;
    Widget row(String label, Widget field) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: theme.typography.body.copyWith(
                color: MacosColors.systemGrayColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: field),
        ],
      ),
    );
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Text(item.title, style: theme.typography.title2),
        const SizedBox(height: 2),
        Text(
          item.type,
          style: theme.typography.callout.copyWith(
            color: MacosColors.systemGrayColor,
          ),
        ),
        const SizedBox(height: 16),
        row(
          'Name',
          MacosTextField(controller: TextEditingController(text: item.title)),
        ),
        // NSComboBox-style: type anything, or pick a suggestion.
        row(
          'Platform',
          MacosTextField(
            controller: _platform,
            suffix: MacosPulldownButton(
              icon: CupertinoIcons.chevron_down,
              items: [
                for (final p in spikePlatforms)
                  MacosPulldownMenuItem(
                    title: Text(p),
                    onTap: () => setState(() => _platform.text = p),
                  ),
              ],
            ),
          ),
        ),
        row(
          'Environment',
          Align(
            alignment: Alignment.centerLeft,
            child: MacosPopupButton<String>(
              value: _environment,
              onChanged: (v) => setState(() => _environment = v!),
              items: [
                for (final e in spikeEnvironments)
                  MacosPopupMenuItem(value: e, child: Text(e)),
              ],
            ),
          ),
        ),
        row(
          'Store password',
          const MacosTextField(
            obscureText: true,
            placeholder: '••••••••••',
            readOnly: true,
          ),
        ),
        if (item.file case final file?)
          row('File', Text(file, style: theme.typography.body)),
        row(
          'Expires',
          Text(item.expiry ?? 'No expiry date', style: theme.typography.body),
        ),
        row(
          'Remind me',
          Align(
            alignment: Alignment.centerLeft,
            child: MacosSwitch(
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PushButton(
              controlSize: ControlSize.regular,
              secondary: true,
              onPressed: () {},
              child: const Text('Export…'),
            ),
            const SizedBox(width: 8),
            PushButton(
              controlSize: ControlSize.regular,
              onPressed: () {},
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
