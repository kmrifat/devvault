import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_macos_menu.dart';
import 'desktop_metrics.dart';
import 'desktop_symbols.dart';
import 'desktop_text_field.dart';
import 'desktop_theme.dart';

/// Why the text typed into a [DesktopDateField] isn't a date.
enum DesktopDateProblem {
  /// It doesn't read as a date at all ("next year").
  unreadable,

  /// It reads as a date that doesn't exist (2027-02-30).
  noSuchDate,
}

/// What [DesktopDateField.parse] made of some typed text: a date, nothing
/// (the text is empty), or a [problem].
typedef DesktopDateInput = ({DateTime? date, DesktopDateProblem? problem});

/// A date field: the date in the locale's medium format ("Mar 1, 2027"),
/// a calendar to pick one from, and a Clear action for an optional date.
/// People who type can still type, as `YYYY-MM-DD` or in the medium
/// format.
///
/// [value] and what [onChanged] reports are dates only: local midnight,
/// no time. Typed text reports a date as soon as it reads as one; while it
/// doesn't, [onProblem] says why (and gets null once it does again), so a
/// form can refuse to save a half-typed date. Nothing is ever filled in for
/// the user: opening the calendar alone sets no date.
///
/// - macOS: `MacosTextField` with a calendar button inside its trailing
///   edge that drops macos_ui's graphical `MacosDatePicker` in the macOS
///   menu style, like the date field + calendar popover in Calendar.
/// - Windows: Fluent `TextBox` with a calendar button that opens a flyout
///   holding Fluent's `CalendarView`, as `CalendarDatePicker` does.
/// - Linux: Yaru-themed `TextField` with a calendar button that drops
///   Material's `CalendarDatePicker` in a popover, like GNOME's.
class DesktopDateField extends StatefulWidget {
  const DesktopDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onProblem,
    this.placeholder,
    this.enabled = true,
    this.calendarLabel = 'Show calendar',
    this.clearLabel = 'Clear',
    this.firstDate,
    this.lastDate,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Why the typed text isn't a date, or null once it is one (or empty).
  final ValueChanged<DesktopDateProblem?>? onProblem;

  final String? placeholder;
  final bool enabled;

  /// What screen readers call the calendar button.
  final String calendarLabel;

  /// The calendar's action that empties the field.
  final String clearLabel;

  /// The calendar's range; typed dates aren't limited by it. Default
  /// 1970 to 2199.
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// How dates are shown: the locale's medium format.
  static String format(DateTime date) => DateFormat.yMMMd().format(date);

  /// Reads typed [text] as a date: `YYYY-MM-DD`, the locale's medium
  /// format ("Mar 1, 2027", any case, month spelled out or not) or its
  /// numeric one ("3/1/2027"). Years have four digits, so a date that is
  /// still being typed ("Mar 1, 202") isn't taken for one.
  static DesktopDateInput parse(String text) {
    final typed = text.trim();
    if (typed.isEmpty) return (date: null, problem: null);
    DesktopDateInput found(DateTime d) => d.year >= 1000 && d.year <= 9999
        ? (date: DateTime(d.year, d.month, d.day), problem: null)
        : (date: null, problem: DesktopDateProblem.unreadable);

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(typed);
    if (iso != null) {
      final [year, month, day] = [
        for (final i in [1, 2, 3]) int.parse(iso.group(i)!),
      ];
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return (date: null, problem: DesktopDateProblem.noSuchDate);
      }
      return found(date);
    }
    for (final format in [DateFormat.yMMMd(), DateFormat.yMd()]) {
      try {
        return found(format.parseLoose(typed));
      } on FormatException {
        // Not in this format; a lenient read tells a day that doesn't
        // exist (Feb 30, which it rolls over) from text that isn't a date.
        try {
          format.parse(typed);
          return (date: null, problem: DesktopDateProblem.noSuchDate);
        } on FormatException {
          continue;
        }
      }
    }
    return (date: null, problem: DesktopDateProblem.unreadable);
  }

  @override
  State<DesktopDateField> createState() => _DesktopDateFieldState();
}

bool _sameDay(DateTime? a, DateTime? b) =>
    a == null ? b == null : b != null && DateUtils.isSameDay(a, b);

DateTime? _dateOnly(DateTime? d) => d == null ? null : DateUtils.dateOnly(d);

class _DesktopDateFieldState extends State<DesktopDateField> {
  late final _controller = TextEditingController(text: _text(widget.value));
  final _focus = FocusNode();
  final _flyout = fl.FlyoutController();
  final _menu = MenuController();

  /// The date last shown or reported, so the parent echoing it back
  /// doesn't rewrite what the user is typing.
  late DateTime? _current = _dateOnly(widget.value);

  static String _text(DateTime? date) =>
      date == null ? '' : DesktopDateField.format(date);

  DateTime get _firstDate => widget.firstDate ?? DateTime(1970);
  DateTime get _lastDate => widget.lastDate ?? DateTime(2199, 12, 31);

  /// Where the calendar opens: on the date, else today, inside its range.
  DateTime get _calendarDate {
    final date = _current ?? DateUtils.dateOnly(DateTime.now());
    if (date.isBefore(_firstDate)) return _firstDate;
    if (date.isAfter(_lastDate)) return _lastDate;
    return date;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(DesktopDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _dateOnly(widget.value);
    if (!_sameDay(value, _dateOnly(oldWidget.value)) &&
        !_sameDay(value, _current)) {
      _current = value;
      _controller.text = _text(value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    _flyout.dispose();
    super.dispose();
  }

  /// Leaving the field tidies a typed date into the shown format.
  void _onFocus() {
    if (_focus.hasFocus) return;
    final input = DesktopDateField.parse(_controller.text);
    final date = input.date;
    if (date != null && _controller.text != _text(date)) {
      _controller.text = _text(date);
    }
  }

  void _typed(String text) {
    final input = DesktopDateField.parse(text);
    widget.onProblem?.call(input.problem);
    if (input.problem != null || _sameDay(input.date, _current)) return;
    _current = input.date;
    widget.onChanged(input.date);
  }

  /// A date picked in the calendar, or null from Clear.
  void _pick(DateTime? date) {
    final picked = _dateOnly(date);
    final text = _text(picked);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onProblem?.call(null);
    if (_sameDay(picked, _current)) return;
    _current = picked;
    widget.onChanged(picked);
  }

  void _close() {
    if (_menu.isOpen) _menu.close();
    if (_flyout.isOpen) _flyout.close<void>();
  }

  void _toggle() {
    if (!widget.enabled) return;
    switch (context.desktopKit) {
      case DesktopKit.fluent:
        _flyout.isOpen ? _flyout.close<void>() : _showFlyout();
      case DesktopKit.macos || DesktopKit.yaru:
        _menu.isOpen ? _menu.close() : _menu.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final kit = context.desktopKit;
    final colors = context.desktopColors;
    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): _toggle,
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _toggle,
      },
      child: DesktopTextField(
        controller: _controller,
        focusNode: _focus,
        placeholder: widget.placeholder,
        enabled: widget.enabled,
        onChanged: _typed,
        onSubmitted: (_) => _onFocus(),
        suffix: _CalendarButton(
          label: widget.calendarLabel,
          enabled: widget.enabled,
          onPressed: _toggle,
        ),
      ),
    );
    return switch (kit) {
      DesktopKit.fluent => fl.FlyoutTarget(controller: _flyout, child: field),
      DesktopKit.macos => _Popover(
        controller: _menu,
        panel: (child) {
          // The macOS menu look, shared with the pop-ups and combo boxes.
          final style = MacosMenuStyle.panel(colors);
          return Material(
            color: style.backgroundColor?.resolve(const {}),
            elevation: style.elevation?.resolve(const {}) ?? 8,
            shape: style.shape?.resolve(const {}),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding:
                  style.padding?.resolve(const {}) ??
                  const EdgeInsets.all(MacosMenuStyle.padding),
              child: child,
            ),
          );
        },
        content: SizedBox(
          width: _macosCalendarWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MacosCalendar(
                date: _calendarDate,
                selected: _current,
                onPick: _pickAndClose,
              ),
              if (_current != null) ...[
                Divider(
                  height: 9,
                  thickness: 0.5,
                  color: colors.innerSeparator,
                ),
                MacosMenuStyle.item(
                  context,
                  label: widget.clearLabel,
                  width: _macosCalendarWidth + 2 * MacosMenuStyle.padding,
                  onPressed: () => _pickAndClose(null),
                ),
              ],
            ],
          ),
        ),
        child: field,
      ),
      DesktopKit.yaru => _Popover(
        controller: _menu,
        panel: (child) {
          final menu = Theme.of(context).popupMenuTheme;
          return Material(
            color: menu.color ?? Theme.of(context).colorScheme.surface,
            elevation: menu.elevation ?? 4,
            shape:
                menu.shape ??
                const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
            clipBehavior: Clip.antiAlias,
            child: child,
          );
        },
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox.fromSize(
              size: _materialCalendarSize,
              child: CalendarDatePicker(
                initialDate: _current == null ? null : _calendarDate,
                currentDate: DateUtils.dateOnly(DateTime.now()),
                firstDate: _firstDate,
                lastDate: _lastDate,
                onDateChanged: _pickAndClose,
              ),
            ),
            if (_current != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: TextButton(
                  onPressed: () => _pickAndClose(null),
                  child: Text(widget.clearLabel),
                ),
              ),
          ],
        ),
        child: field,
      ),
    };
  }

  void _pickAndClose(DateTime? date) {
    _pick(date);
    _close();
  }

  void _showFlyout() {
    _flyout.showFlyout<void>(
      barrierColor: Colors.transparent,
      autoModeConfiguration: fl.FlyoutAutoConfiguration(
        preferredMode: fl.FlyoutPlacementMode.bottomLeft,
      ),
      builder: (context) => fl.FlyoutContent(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              SizedBox(
                width: _fluentCalendarWidth,
                child: fl.CalendarView(
                  initialStart: _current,
                  minDate: _firstDate,
                  maxDate: _lastDate,
                  onSelectionChanged: (selection) {
                    // Tapping the chosen day again unselects it in Fluent's
                    // calendar; that isn't a choice, Clear is.
                    final date = selection.startDate;
                    if (date != null) _pickAndClose(date);
                  },
                ),
              ),
              if (_current != null)
                fl.Button(
                  onPressed: () => _pickAndClose(null),
                  child: Text(widget.clearLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The calendar button inside the field's trailing edge.
class _CalendarButton extends StatelessWidget {
  const _CalendarButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final kit = context.desktopKit;
    final icon = Icon(
      DesktopSymbol.calendar.of(kit),
      size: kit == DesktopKit.macos ? 13 : 14,
      color: enabled ? colors.secondaryText : colors.tertiaryText,
    );
    return switch (kit) {
      DesktopKit.macos => Semantics(
        button: true,
        enabled: enabled,
        label: label,
        // The whole end of the field opens the calendar, not just the
        // icon: a full-height target, as in the combo box.
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: SizedBox(
              width: DesktopMetrics.fieldHeight,
              height: DesktopMetrics.fieldHeight - 6,
              child: icon,
            ),
          ),
        ),
      ),
      DesktopKit.fluent => Semantics(
        button: true,
        label: label,
        child: fl.IconButton(icon: icon, onPressed: enabled ? onPressed : null),
      ),
      DesktopKit.yaru => IconButton(
        tooltip: label,
        icon: icon,
        onPressed: enabled ? onPressed : null,
      ),
    };
  }
}

/// macos_ui's graphical date picker is this wide.
const double _macosCalendarWidth = 138 + 8;
const double _fluentCalendarWidth = 300;
const Size _materialCalendarSize = Size(320, 346);

/// macos_ui's graphical `MacosDatePicker`, flush in the menu panel.
///
/// The kit's picker reports every change of its own state: a day clicked,
/// but also the 1st of the month its arrows move to. Only a day clicked in
/// the month on show is a pick; moving between months just turns pages.
class _MacosCalendar extends StatefulWidget {
  const _MacosCalendar({
    required this.date,
    required this.selected,
    required this.onPick,
  });

  /// The month to open on (and its selected day).
  final DateTime date;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  @override
  State<_MacosCalendar> createState() => _MacosCalendarState();
}

class _MacosCalendarState extends State<_MacosCalendar> {
  late DateTime _month = DateTime(widget.date.year, widget.date.month);

  void _changed(DateTime date) {
    if (date.year == _month.year && date.month == _month.month) {
      widget.onPick(date);
    } else {
      _month = DateTime(date.year, date.month);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final theme = mac.MacosDatePickerTheme.of(context);
    return mac.MacosDatePickerTheme(
      data: theme.copyWith(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        monthViewSelectedDateColor: widget.selected == null
            ? Colors.transparent
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.text),
        child: SizedBox(
          width: _macosCalendarWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
            child: mac.MacosDatePicker(
              style: mac.DatePickerStyle.graphical,
              initialDate: widget.date,
              onDateChanged: _changed,
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel under its anchor (above it when there's no room below), closed
/// by Esc or a click outside. Unlike [MenuAnchor] it doesn't measure its
/// content's intrinsic width, which a calendar's grid can't give.
class _Popover extends StatelessWidget {
  const _Popover({
    required this.controller,
    required this.panel,
    required this.content,
    required this.child,
  });

  final MenuController controller;
  final Widget Function(Widget child) panel;
  final Widget content;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
    controller: controller,
    overlayBuilder: (context, info) => Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _PopoverLayout(info.anchorRect),
        child: TapRegion(
          groupId: info.tapRegionGroupId,
          // Focus moves into the panel, so Esc closes it.
          child: Focus(
            autofocus: true,
            // Scrolls in a window too short for it.
            child: panel(SingleChildScrollView(child: content)),
          ),
        ),
      ),
    ),
    child: child,
  );
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor);

  final Rect anchor;
  static const double _gap = 4;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest)
          .deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + _gap;
    final above = anchor.top - _gap - childSize.height;
    final fitsBelow = below + childSize.height <= size.height - _margin;
    final fitsAbove = above >= _margin;
    // Where it fits; else on the roomier side, pulled back into the
    // window.
    final y = fitsBelow || (!fitsAbove && anchor.center.dy < size.height / 2)
        ? below
        : above;
    final x = anchor.left.clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );
    final maxY = (size.height - childSize.height - _margin).clamp(
      _margin,
      double.infinity,
    );
    return Offset(x, y.clamp(_margin, maxY));
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}
