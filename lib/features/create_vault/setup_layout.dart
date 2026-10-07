import '../../app/layout.dart';
import '../../shared/ui.dart';

/// The first-run screens' frame (design frames D01, D02): a steps rail
/// beside the content on desktop, the content alone on phones.
class SetupLayout extends StatelessWidget {
  const SetupLayout({
    super.key,
    required this.step,
    required this.child,
    this.layout,
  });

  /// 1 = master password, 2 = recovery kit, 3 = sync (optional).
  final int step;
  final Widget child;
  final AppLayout? layout;

  static const steps = [
    ('Master password', 'Unlocks the vault on every device'),
    ('Recovery kit', 'The only way back if you forget it'),
    ('Sync storage · optional', 'Your own S3-compatible bucket'),
  ];

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final desktop = MediaQuery.sizeOf(context).width >= BCBreakpoints.tablet;
    final content = SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 72 : BCSpacing.lg,
            vertical: desktop ? 64 : BCSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: child,
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: bc.background,
      body: desktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepsRail(step: step),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}

class _StepsRail extends StatelessWidget {
  const _StepsRail({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: bc.backgroundSecondary,
        border: Border(right: BorderSide(color: bc.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        BCSpacing.lg,
        60,
        BCSpacing.lg,
        BCSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 28,
        children: [
          Row(
            spacing: BCSpacing.sm + 2,
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: bc.accentSoft,
                  shape: BCShapes.continuous(BCRadius.xl),
                ),
                child: SizedBox.square(
                  dimension: 36,
                  child: Icon(LucideIcons.vault, size: 18, color: bc.accent),
                ),
              ),
              const BCText('DevVault', type: BCTextType.h5),
            ],
          ),
          Column(
            spacing: BCSpacing.xs,
            children: [
              for (final (i, (title, subtitle)) in SetupLayout.steps.indexed)
                _Step(
                  number: i + 1,
                  title: title,
                  subtitle: i + 1 < step ? 'Done' : subtitle,
                  state: i + 1 < step
                      ? _StepState.done
                      : i + 1 == step
                      ? _StepState.current
                      : _StepState.upcoming,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final int number;
  final String title;
  final String subtitle;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final current = state == _StepState.current;
    return Semantics(
      selected: current,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: current ? bc.accentSoft : null,
          shape: BCShapes.continuous(BCRadius.xxl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: switch (state) {
                    _StepState.done => bc.successSoft,
                    _StepState.current => bc.accent,
                    _StepState.upcoming => bc.defaultColor,
                  },
                  shape: const CircleBorder(),
                ),
                child: SizedBox.square(
                  dimension: 26,
                  child: Center(
                    child: state == _StepState.done
                        ? Icon(
                            LucideIcons.check,
                            size: 14,
                            color: bc.successSoftForeground,
                          )
                        : Text(
                            '$number',
                            style: BCTypography.textXs.copyWith(
                              fontWeight: BCTypography.bold,
                              color: current ? bc.accentForeground : bc.muted,
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    BCText(
                      title,
                      type: BCTextType.bodySm,
                      weight: BCTextWeight.semibold,
                      color: current
                          ? BCTextColor.foreground
                          : BCTextColor.muted,
                    ),
                    BCText(
                      subtitle,
                      type: BCTextType.bodyXs,
                      color: BCTextColor.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
