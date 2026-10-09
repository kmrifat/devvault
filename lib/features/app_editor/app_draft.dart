import 'package:vault_core/vault_core.dart';

/// One identifier row of the app form. [kindName] is null until the user
/// picks a kind: nothing guesses it from the value.
class DraftIdentifier {
  DraftIdentifier({
    this.kindName,
    this.value = '',
    this.unknownFields = const {},
  });

  factory DraftIdentifier.of(AppIdentifier id) => DraftIdentifier(
    kindName: id.kindName,
    value: id.value,
    unknownFields: id.unknownFields,
  );

  String? kindName;
  String value;

  /// Fields a newer version stored on this entry, kept through the edit.
  final Map<String, Object?> unknownFields;

  IdentifierKind? get kind =>
      kindName == null ? null : IdentifierKind.fromWireName(kindName!);
}

/// What the app form edits, before it becomes an [AppRecord]. Kept apart
/// from the widgets so the rules can be tested on their own.
class AppDraft {
  AppDraft._({
    required this.name,
    required this.organization,
    required this.kindName,
    required this.identifiers,
    this.base,
  });

  /// A new app; [organization] is set when the user started it from an
  /// organization in the sidebar.
  factory AppDraft.create({String? organization}) => AppDraft._(
    name: '',
    organization: organization ?? '',
    kindName: null,
    identifiers: [],
  );

  factory AppDraft.edit(AppRecord app) => AppDraft._(
    base: app,
    name: app.name,
    organization: app.organization ?? '',
    kindName: app.kindName,
    identifiers: [for (final id in app.allIdentifiers) DraftIdentifier.of(id)],
  );

  /// The app being edited; null when creating one.
  final AppRecord? base;
  String name;

  /// As typed; empty means none.
  String organization;

  /// The chosen [AppKind.wireName] (or a newer kind kept from [base]);
  /// null is "Not set".
  String? kindName;

  /// In the order the form shows them.
  final List<DraftIdentifier> identifiers;

  bool get isNew => base == null;

  /// Apple bundle IDs: reverse-DNS, letters, digits, hyphens and dots.
  static final _bundleId = RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');

  /// Android application IDs: dot-separated Java identifiers, two or more.
  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  /// Problems that stop saving, keyed `name`, or `id<i>` for the
  /// identifier at index i. [others] are the vault's other apps, whose
  /// names this one mustn't repeat. Rows left empty are dropped on save.
  Map<String, String> validate(Iterable<AppRecord> others) {
    final errors = <String, String>{};
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      errors['name'] = 'Give the app a name';
    } else if (others.any(
      (a) => a.id != base?.id && a.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      errors['name'] = 'Another app has this name';
    }
    for (final (i, id) in identifiers.indexed) {
      final value = id.value.trim();
      if (value.isEmpty) continue;
      final problem = switch (id.kind) {
        _ when id.kindName == null => 'Choose what kind of identifier this is',
        IdentifierKind.bundleId when !_bundleId.hasMatch(value) =>
          'Not a bundle ID: $value',
        IdentifierKind.packageName when !_packageName.hasMatch(value) =>
          'Not a package name: $value',
        _ => null,
      };
      if (problem != null) errors['id$i'] = problem;
    }
    return errors;
  }

  /// The app to save: a fresh one from [newApp] when creating, else the
  /// edited copy of [base]. Call [validate] first. The record trims values
  /// and drops empty and repeated ones (SPEC §6.2).
  AppRecord toApp(AppRecord Function(String name) newApp) {
    final start = base ?? newApp(name.trim());
    return start.copyWith(
      name: name.trim(),
      // An empty string clears them.
      organization: organization,
      kindName: kindName ?? '',
      identifiers: [
        for (final id in identifiers)
          if (id.kindName case final kind?)
            AppIdentifier(kind, id.value, unknownFields: id.unknownFields),
      ],
    );
  }
}
