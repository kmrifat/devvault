import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../../app/theme.dart' show AppText;

/// What a [MarkdownNote] draws with. Each layout builds one from its own
/// theme: the desktop layer's colours and sizes, or bc_ui's on a phone.
@immutable
class MarkdownNoteStyle {
  const MarkdownNoteStyle({
    required this.body,
    required this.secondaryColor,
    required this.linkColor,
    required this.codeBackground,
    required this.ruleColor,
    required this.headingSizes,
    required this.codeRadius,
    required this.hintBackground,
    required this.hintColor,
    this.blockGap = 8,
    this.listIndent = 20,
  });

  /// Paragraph text: size, line height and colour. Everything else is
  /// derived from it.
  final TextStyle body;

  /// Quotes, list markers and the stand-in for an image.
  final Color secondaryColor;
  final Color linkColor;

  /// Behind code spans and code blocks.
  final Color codeBackground;

  /// Horizontal rules, the bar beside a quote, a code block's outline.
  final Color ruleColor;

  /// Heading 1, 2 and 3; smaller headings use the body size, in bold.
  final List<double> headingSizes;
  final double codeRadius;

  /// The box that shows where a hovered link goes (desktop).
  final Color hintBackground;
  final Color hintColor;

  /// Between blocks: paragraphs, lists, quotes, code.
  final double blockGap;

  /// How far a list item's text sits from the list's edge.
  final double listIndent;
}

/// A note shown as Markdown (CommonMark, SPEC §6.6): headings, emphasis,
/// lists, quotes, code spans and blocks (in mono), links and rules. Single
/// line breaks are kept, as people type them in a note.
///
/// It is a safe subset, built from the `markdown` package's syntax tree
/// rather than from HTML:
///
/// - **Nothing is fetched.** An image is never loaded, from the network or
///   from disk: it shows as "[Image: alt text]" (or its URL when it has no
///   alt text).
/// - **No HTML.** Raw HTML, inline or as a block, shows as the text it is.
/// - **Links don't open.** A link is drawn as one; clicking or tapping it
///   calls [onLink] with its URL, and the caller decides what that does
///   (DevVault copies it). With [showLinkOnHover] (desktop), pointing at a
///   link shows its URL first.
///
/// The text is selectable.
class MarkdownNote extends StatefulWidget {
  const MarkdownNote(
    this.markdown, {
    super.key,
    required this.style,
    required this.onLink,
    this.showLinkOnHover = false,
  });

  final String markdown;
  final MarkdownNoteStyle style;

  /// Called with a link's URL when it is clicked or tapped.
  final ValueChanged<String> onLink;

  /// Shows a link's URL next to the pointer while it hovers the link.
  final bool showLinkOnHover;

  /// Parses [markdown] with raw HTML kept as text.
  static List<md.Node> parse(String markdown) => md.Document(
    extensionSet: md.ExtensionSet.commonMark,
    encodeHtml: false,
  ).parse(markdown.replaceAll('\r\n', '\n'));

  /// The note's first line as plain text, without Markdown: a one-line
  /// preview.
  static String firstLine(String markdown) => _firstLine(parse(markdown));

  /// The elements that sit inside a paragraph.
  static const _inlineTags = {'em', 'strong', 'code', 'a', 'img', 'br', 'del'};

  static String _firstLine(List<md.Node> nodes) {
    final inline = StringBuffer();
    for (final node in nodes) {
      final container =
          node is md.Element &&
          const {'ul', 'ol', 'li', 'blockquote'}.contains(node.tag);
      if (!container) {
        final block = node is md.Element && !_inlineTags.contains(node.tag);
        inline.write(block ? '${node.textContent}\n' : node.textContent);
        continue;
      }
      // A list or quote: the text before it, else its own first line.
      final before = _firstOf(inline.toString());
      if (before.isNotEmpty) return before;
      inline.clear();
      final within = _firstLine(node.children ?? const []);
      if (within.isNotEmpty) return within;
    }
    return _firstOf(inline.toString());
  }

  static String _firstOf(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');

  @override
  State<MarkdownNote> createState() => _MarkdownNoteState();
}

class _MarkdownNoteState extends State<MarkdownNote> {
  late List<md.Node> _nodes = MarkdownNote.parse(widget.markdown);
  final _recognizers = <TapGestureRecognizer>[];
  final _hint = OverlayPortalController();
  String? _hovered;
  Offset _pointer = Offset.zero;

  @override
  void didUpdateWidget(MarkdownNote old) {
    super.didUpdateWidget(old);
    if (old.markdown != widget.markdown) {
      _nodes = MarkdownNote.parse(widget.markdown);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _enter(String url, PointerEnterEvent event) {
    if (!widget.showLinkOnHover) return;
    setState(() {
      _hovered = url;
      _pointer = event.position;
    });
    _hint.show();
  }

  void _exit(String url) {
    if (_hovered != url) return;
    _hint.hide();
    setState(() => _hovered = null);
  }

  TextStyle get _body => widget.style.body;

  TextStyle get _mono => _body.copyWith(
    fontFamily: AppText.monoFamily,
    fontSize: (_body.fontSize ?? 14) * 0.92,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final blocks = _blocks(_nodes, _body);
    return OverlayPortal(
      controller: _hint,
      overlayChildBuilder: _linkHint,
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: widget.style.blockGap,
          children: blocks,
        ),
      ),
    );
  }

  /// Where the hovered link goes, just below and right of the pointer.
  Widget _linkHint(BuildContext context) {
    final url = _hovered;
    if (url == null) return const SizedBox.shrink();
    final overlay = Overlay.of(context).context.findRenderObject();
    final at = overlay is RenderBox
        ? overlay.globalToLocal(_pointer)
        : _pointer;
    final style = widget.style;
    final size = (_body.fontSize ?? 14) * 0.85;
    return Positioned(
      left: at.dx + 12,
      top: at.dy + 18,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: style.hintBackground,
              border: Border.all(color: style.ruleColor, width: 0.5),
              borderRadius: BorderRadius.all(Radius.circular(style.codeRadius)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '$url\nClick to copy the link',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size,
                  height: 1.3,
                  color: style.hintColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _isInline(md.Node node) =>
      node is md.Text ||
      (node is md.Element && MarkdownNote._inlineTags.contains(node.tag));

  /// Block-level [nodes] as widgets. Runs of inline nodes (a tight list
  /// item's text) become one paragraph.
  List<Widget> _blocks(List<md.Node> nodes, TextStyle style) {
    final out = <Widget>[];
    final run = <md.Node>[];
    void flush() {
      if (run.isEmpty) return;
      out.add(_paragraph(List.of(run), style));
      run.clear();
    }

    for (final node in nodes) {
      if (_isInline(node)) {
        // Raw HTML blocks arrive as bare text: shown as typed.
        run.add(node);
        continue;
      }
      flush();
      if (node is md.Element) out.add(_block(node, style));
    }
    flush();
    return out;
  }

  Widget _block(md.Element node, TextStyle style) {
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        final sizes = widget.style.headingSizes;
        return Semantics(
          header: true,
          child: _paragraph(
            children,
            style.copyWith(
              fontSize: level <= sizes.length ? sizes[level - 1] : null,
              fontWeight: level <= 2 ? FontWeight.w700 : FontWeight.w600,
              height: 1.25,
            ),
          ),
        );
      case 'p':
        return _paragraph(children, style);
      case 'blockquote':
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: widget.style.ruleColor, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: widget.style.blockGap,
              children: _blocks(
                children,
                style.copyWith(color: widget.style.secondaryColor),
              ),
            ),
          ),
        );
      case 'ul' || 'ol':
        return _list(node, style);
      case 'pre':
        return _codeBlock(node.textContent);
      case 'hr':
        return SizedBox(
          height: 1,
          child: ColoredBox(color: widget.style.ruleColor),
        );
      default:
        // Anything else the parser makes: its content, as blocks.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: widget.style.blockGap,
          children: _blocks(children, style),
        );
    }
  }

  Widget _list(md.Element list, TextStyle style) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = (list.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: widget.style.blockGap / 2,
      children: [
        for (final (i, item) in items.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.style.listIndent,
                child: Text(
                  ordered ? '${start + i}.' : '•',
                  style: style.copyWith(color: widget.style.secondaryColor),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: widget.style.blockGap / 2,
                  children: _blocks(item.children ?? const [], style),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _codeBlock(String code) {
    final text = code.endsWith('\n')
        ? code.substring(0, code.length - 1)
        : code;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.style.codeBackground,
        border: Border.all(color: widget.style.ruleColor, width: 0.5),
        borderRadius: BorderRadius.all(
          Radius.circular(widget.style.codeRadius),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text, softWrap: false, style: _mono),
      ),
    );
  }

  Widget _paragraph(List<md.Node> nodes, TextStyle style) {
    final spans = _inline(nodes, style, null);
    // Text that ends a block (a raw HTML block, a list item) may carry the
    // line break before the next one.
    return Text.rich(TextSpan(children: _trimEnds(spans)), style: style);
  }

  /// [spans] without the line breaks at the very start and end.
  static List<InlineSpan> _trimEnds(List<InlineSpan> spans) {
    if (spans.isEmpty) return spans;
    TextSpan trim(TextSpan s, {required bool start}) => TextSpan(
      text: start
          ? s.text!.replaceFirst(RegExp(r'^\n+'), '')
          : s.text!.replaceFirst(RegExp(r'\n+$'), ''),
      style: s.style,
      recognizer: s.recognizer,
      mouseCursor: s.mouseCursor,
      onEnter: s.onEnter,
      onExit: s.onExit,
    );
    final out = List.of(spans);
    if (out.first case final TextSpan first when first.text != null) {
      out[0] = trim(first, start: true);
    }
    if (out.last case final TextSpan last when last.text != null) {
      out[out.length - 1] = trim(last, start: false);
    }
    return out;
  }

  List<InlineSpan> _inline(List<md.Node> nodes, TextStyle style, String? href) {
    final out = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        out.add(_text(node.text, style, href));
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'em':
          out.addAll(
            _inline(
              children,
              style.copyWith(fontStyle: FontStyle.italic),
              href,
            ),
          );
        case 'strong':
          out.addAll(
            _inline(
              children,
              style.copyWith(fontWeight: FontWeight.w700),
              href,
            ),
          );
        case 'del':
          out.addAll(
            _inline(
              children,
              style.copyWith(decoration: TextDecoration.lineThrough),
              href,
            ),
          );
        case 'code':
          out.add(
            _text(
              node.textContent,
              _mono.copyWith(
                color: style.color,
                backgroundColor: widget.style.codeBackground,
              ),
              href,
            ),
          );
        case 'br':
          out.add(const TextSpan(text: '\n'));
        case 'a':
          final url = node.attributes['href'] ?? '';
          out.addAll(
            _inline(
              children,
              style.copyWith(
                color: widget.style.linkColor,
                decoration: TextDecoration.underline,
                decorationColor: widget.style.linkColor,
              ),
              url,
            ),
          );
        case 'img':
          // Never loaded: what the image is, in words.
          final alt = node.attributes['alt']?.trim() ?? '';
          final src = node.attributes['src'] ?? '';
          out.add(
            _text(
              '[Image: ${alt.isNotEmpty ? alt : src}]',
              style.copyWith(
                color: href == null ? widget.style.secondaryColor : null,
              ),
              href,
            ),
          );
        default:
          out.addAll(_inline(children, style, href));
      }
    }
    return out;
  }

  TextSpan _text(String text, TextStyle style, String? href) {
    if (href == null) return TextSpan(text: text, style: style);
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onLink(href);
    _recognizers.add(recognizer);
    return TextSpan(
      text: text,
      style: style,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.click,
      onEnter: (event) => _enter(href, event),
      onExit: (_) => _exit(href),
    );
  }
}
