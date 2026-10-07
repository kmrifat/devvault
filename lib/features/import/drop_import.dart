import 'package:desktop_drop/desktop_drop.dart';

import '../../shared/ui.dart';
import 'import_dialog.dart';
import 'import_draft.dart';

/// Lets files be dropped anywhere on [child] to import them (design frame
/// D04's third entry point, next to the toolbar and ⌘I). While files are
/// dragged over it, it says so.
class ImportDropTarget extends StatefulWidget {
  const ImportDropTarget({super.key, required this.child});

  final Widget child;

  /// The dropped files with their bytes. Folders are skipped: an import is
  /// one item per file.
  static Future<List<PickedFile>> read(List<DropItem> items) async => [
    for (final item in items)
      if (item is! DropItemDirectory)
        PickedFile(
          name: item.name.isNotEmpty
              ? item.name
              : item.path.split(RegExp(r'[/\\]')).last,
          bytes: await item.readAsBytes(),
        ),
  ];

  @override
  State<ImportDropTarget> createState() => _ImportDropTargetState();
}

class _ImportDropTargetState extends State<ImportDropTarget> {
  bool _over = false;

  Future<void> _drop(DropDoneDetails details) async {
    setState(() => _over = false);
    // Not on top of another dialog: one import at a time.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final files = await ImportDropTarget.read(details.files);
    if (files.isEmpty || !mounted) return;
    await showImportDialog(context, files: files);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: _drop,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(BCSpacing.md),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: bc.accentSoft,
                      shape: BCShapes.continuous(
                        BCRadius.xxl,
                        side: BorderSide(color: bc.accent, width: 2),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: BCSpacing.sm,
                        children: [
                          Icon(
                            LucideIcons.filePlus2,
                            size: 32,
                            color: bc.accentSoftForeground,
                          ),
                          BCText(
                            'Drop to import',
                            type: BCTextType.h4,
                            style: TextStyle(color: bc.accentSoftForeground),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
