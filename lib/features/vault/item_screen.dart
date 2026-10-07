import '../../shared/ui.dart';
import 'item_detail_pane.dart';

/// Design frame B3: one item on a phone, pushed from the list. The same
/// detail as the desktop pane in its compact layout; Export opens the
/// share sheet there (ShareSheetSaver).
class ItemScreen extends StatelessWidget {
  const ItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    // The item's own header carries the title; the bar only goes back.
    return Scaffold(
      backgroundColor: context.bcTheme.background,
      appBar: const BCAppHeader(variant: BCAppHeaderVariant.solid),
      body: ItemDetailPane(itemId: itemId, compact: true),
    );
  }
}
