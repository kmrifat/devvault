import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../shared/ui.dart';
import 'item_detail_pane.dart';

/// Design frame B3: one item on a phone, pushed from the list. Export
/// opens the share sheet there (ShareSheetSaver).
class ItemScreen extends ConsumerWidget {
  const ItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The item's own header carries the title; the bar only goes back. On
    // iPhone the bar is UIKit's.
    return Scaffold(
      backgroundColor: context.bcTheme.background,
      appBar: ref.watch(nativeBarsProvider)
          ? NativePhoneHeader(
              title: '',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go(Routes.vault()),
            )
          : const BCAppHeader(variant: BCAppHeaderVariant.solid),
      body: ItemDetailPane(itemId: itemId),
    );
  }
}
