import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// How the editor draws a block's inline Markdown while it is edited.
@immutable
class InlineMarkdownLook {
  const InlineMarkdownLook({
    required this.markColor,
    required this.linkColor,
    required this.secondaryColor,
    required this.codeBackground,
    required this.monoFamily,
  });

  /// The `**`, `` ` `` and `[](…)` marks, where they show.
  final Color markColor;
  final Color linkColor;

  /// An image's alt text (images are never loaded).
  final Color secondaryColor;
  final Color codeBackground;
  final String monoFamily;
}

/// A style that takes no room and draws nothing: marks outside the block
/// being edited.
const hiddenMarkStyle = TextStyle(
  fontSize: 0.01,
  color: Color(0x00000000),
  letterSpacing: 0,
  height: 0,
);

/// [text] as spans with its inline Markdown applied: `**bold**`,
/// `__bold__`, `*italic*`, `_italic_`, `~~struck~~`, `` `code` ``, links
/// and backslash escapes. The text itself is never changed: every
/// character, marks included, is in exactly one span, so offsets in the
/// spans are offsets in [text]. [showMarks] draws the marks faintly
/// (the block being edited); otherwise they take no room.
List<InlineSpan> inlineMarkdownSpans(
  String text,
  TextStyle style,
  InlineMarkdownLook look, {
  required bool showMarks,
}) {
  final out = <InlineSpan>[];
  _InlineScanner(look, showMarks, out).scan(text, style);
  return out;
}

class _InlineScanner {
  _InlineScanner(this.look, this.showMarks, this.out);

  final InlineMarkdownLook look;
  final bool showMarks;
  final List<InlineSpan> out;

  static final _punctuation = RegExp(
    r'''[!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~]''',
  );
  static final _word = RegExp(r'[A-Za-z0-9]');

  void mark(String s, TextStyle style) => out.add(
    TextSpan(
      text: s,
      style: showMarks
          ? style.copyWith(
              color: look.markColor,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              decoration: TextDecoration.none,
              backgroundColor: const Color(0x00000000),
            )
          : hiddenMarkStyle,
    ),
  );

  void scan(String s, TextStyle style) {
    final plain = StringBuffer();
    void flush() {
      if (plain.isEmpty) return;
      out.add(TextSpan(text: plain.toString(), style: style));
      plain.clear();
    }

    var i = 0;
    while (i < s.length) {
      final c = s[i];

      // \* shows a star: the backslash is a mark.
      if (c == r'\' && i + 1 < s.length && _punctuation.hasMatch(s[i + 1])) {
        flush();
        mark(c, style);
        plain.write(s[i + 1]);
        i += 2;
        continue;
      }

      // `code`: a run of backticks up to the same run.
      if (c == '`') {
        var n = 1;
        while (i + n < s.length && s[i + n] == '`') {
          n++;
        }
        final run = '`' * n;
        final close = _closingRun(s, run, i + n);
        if (close != -1 && close > i + n) {
          flush();
          mark(run, style);
          out.add(
            TextSpan(
              text: s.substring(i + n, close),
              style: style.copyWith(
                fontFamily: look.monoFamily,
                fontSize: (style.fontSize ?? 14) * 0.92,
                backgroundColor: look.codeBackground,
              ),
            ),
          );
          mark(run, style);
          i = close + n;
        } else {
          plain.write(run);
          i += n;
        }
        continue;
      }

      // **bold**, __bold__, ~~struck~~.
      var matched = false;
      for (final (pair, inner) in [
        ('**', style.copyWith(fontWeight: FontWeight.w700)),
        ('__', style.copyWith(fontWeight: FontWeight.w700)),
        ('~~', style.copyWith(decoration: TextDecoration.lineThrough)),
      ]) {
        if (!s.startsWith(pair, i)) continue;
        final close = _closing(s, pair, i + 2);
        if (close == -1 || (pair == '__' && !_flanked(s, i, close + 2))) {
          continue;
        }
        flush();
        mark(pair, style);
        scan(s.substring(i + 2, close), inner);
        mark(pair, style);
        i = close + 2;
        matched = true;
        break;
      }
      if (matched) continue;

      // *italic*, _italic_.
      if ((c == '*' || c == '_') &&
          !(i + 1 < s.length && s[i + 1] == c) &&
          i + 1 < s.length &&
          s[i + 1] != ' ') {
        final close = _closing(s, c, i + 1);
        if (close != -1 && (c == '*' || _flanked(s, i, close + 1))) {
          flush();
          mark(c, style);
          scan(
            s.substring(i + 1, close),
            style.copyWith(fontStyle: FontStyle.italic),
          );
          mark(c, style);
          i = close + 1;
          continue;
        }
      }

      // [text](url) and ![alt](url).
      final image = c == '!' && i + 1 < s.length && s[i + 1] == '[';
      if (c == '[' || image) {
        final open = image ? i + 1 : i;
        final link = _link(s, open);
        if (link != null) {
          final (textEnd, urlEnd) = link;
          flush();
          mark(s.substring(i, open + 1), style);
          final label = s.substring(open + 1, textEnd);
          if (image) {
            out.add(
              TextSpan(
                text: label,
                style: style.copyWith(color: look.secondaryColor),
              ),
            );
          } else {
            scan(
              label,
              style.copyWith(
                color: look.linkColor,
                decoration: TextDecoration.underline,
                decorationColor: look.linkColor,
              ),
            );
          }
          mark(s.substring(textEnd, urlEnd + 1), style);
          i = urlEnd + 1;
          continue;
        }
      }

      plain.write(c);
      i++;
    }
    flush();
  }

  /// Where [run] (backticks) appears again from [from], as a whole run.
  static int _closingRun(String s, String run, int from) {
    var at = s.indexOf(run, from);
    while (at != -1) {
      final before = at > 0 && s[at - 1] == '`';
      final after = at + run.length < s.length && s[at + run.length] == '`';
      if (!before && !after) return at;
      at = s.indexOf(run, at + 1);
    }
    return -1;
  }

  /// The closing [mark] after [from], with something between and no
  /// space just inside it.
  static int _closing(String s, String mark, int from) {
    var at = s.indexOf(mark, from);
    while (at != -1) {
      final single = mark.length == 1;
      final doubled =
          single &&
          ((at + 1 < s.length && s[at + 1] == mark) ||
              (at > from && s[at - 1] == mark));
      if (at > from && s[at - 1] != ' ' && !doubled) return at;
      at = s.indexOf(mark, at + 1);
    }
    return -1;
  }

  /// Underscores emphasize only between non-word characters: `snake_case`
  /// stays as it is.
  static bool _flanked(String s, int open, int closeEnd) {
    final before = open > 0 && _word.hasMatch(s[open - 1]);
    final after = closeEnd < s.length && _word.hasMatch(s[closeEnd]);
    return !before && !after;
  }

  /// A link at [open] (its `[`): where its text ends (the `]`) and its URL
  /// ends (the `)`), or null.
  static (int, int)? _link(String s, int open) {
    var depth = 0;
    for (var j = open + 1; j < s.length; j++) {
      final ch = s[j];
      if (ch == r'\') {
        j++;
        continue;
      }
      if (ch == '[') depth++;
      if (ch == ']') {
        if (depth > 0) {
          depth--;
          continue;
        }
        if (j + 1 >= s.length || s[j + 1] != '(') return null;
        final close = s.indexOf(')', j + 2);
        if (close == -1) return null;
        final url = s.substring(j + 2, close);
        if (url.contains(' ') && !url.contains('"')) return null;
        return (j, close);
      }
    }
    return null;
  }
}
