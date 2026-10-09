import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The toasts on screen: bc_ui's cards on phones, the desktop layer's
/// banners and snackbars (`showDesktopToast`) and Fluent's `InfoBar`s.
/// Neither bc_ui nor the desktop layer exports its toast widget, so this
/// matches them by type name; [toastTexts] fails loudly if that ever
/// changes.
final _toastCards = find.byWidgetPredicate(
  (w) => const {
    '_BCToastCard',
    '_Toast',
    'InfoBar',
  }.contains(w.runtimeType.toString()),
);

/// Every piece of text in the toasts on screen: titles, descriptions and
/// action labels.
List<String> toastTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(
    find.descendant(of: _toastCards, matching: find.byType(RichText)),
  ))
    text.text.toPlainText(),
];

/// Secrets never appear in toasts (PR-3c). Checks the toasts on screen right
/// now, and that there is at least one, so a check placed where no toast
/// shows can't pass by finding nothing.
void expectNoSecretInToasts(WidgetTester tester, Iterable<String> secrets) {
  final texts = toastTexts(tester);
  expect(texts, isNotEmpty, reason: 'no toast is showing');
  for (final secret in secrets) {
    for (final text in texts) {
      expect(
        text.contains(secret),
        isFalse,
        reason: 'a toast shows a secret: "$text"',
      );
    }
  }
}
