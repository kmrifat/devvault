import 'package:vault_core/vault_core.dart';

/// What the app form edits, before it becomes an [AppRecord]. Kept apart
/// from the widgets so the rules can be tested on their own.
class AppDraft {
  AppDraft._({
    required this.name,
    required this.bundleIds,
    required this.packageNames,
    this.base,
  });

  factory AppDraft.create() =>
      AppDraft._(name: '', bundleIds: '', packageNames: '');

  factory AppDraft.edit(AppRecord app) => AppDraft._(
    base: app,
    name: app.name,
    bundleIds: app.bundleIds.join('\n'),
    packageNames: app.packageNames.join('\n'),
  );

  /// The app being edited; null when creating one.
  final AppRecord? base;
  String name;

  /// One per line or comma-separated, as typed.
  String bundleIds;
  String packageNames;

  bool get isNew => base == null;

  /// Apple bundle IDs: reverse-DNS, letters, digits, hyphens and dots.
  static final _bundleId = RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');

  /// Android application IDs: dot-separated Java identifiers, two or more.
  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  static List<String> _split(String text) => [
    ...{
      for (final part in text.split(RegExp(r'[,\s]+')))
        if (part.isNotEmpty) part,
    },
  ];

  List<String> get bundleIdList => _split(bundleIds);
  List<String> get packageNameList => _split(packageNames);

  /// Problems that stop saving, keyed `name`, `bundleIds` or
  /// `packageNames`. [others] are the vault's other apps, whose names this
  /// one mustn't repeat.
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
    final badBundle = bundleIdList.where((id) => !_bundleId.hasMatch(id));
    if (badBundle.isNotEmpty) {
      errors['bundleIds'] = 'Not a bundle ID: ${badBundle.first}';
    }
    final badPackage = packageNameList.where(
      (id) => !_packageName.hasMatch(id),
    );
    if (badPackage.isNotEmpty) {
      errors['packageNames'] = 'Not a package name: ${badPackage.first}';
    }
    return errors;
  }

  /// The app to save: a fresh one from [newApp] when creating, else the
  /// edited copy of [base]. Call [validate] first.
  AppRecord toApp(AppRecord Function(String name) newApp) {
    final start = base ?? newApp(name.trim());
    return AppRecord(
      id: start.id,
      name: name.trim(),
      bundleIds: bundleIdList,
      packageNames: packageNameList,
      iconBlobId: start.iconBlobId,
      createdAt: start.createdAt,
      updatedAt: start.updatedAt,
      rev: start.rev,
      deviceId: start.deviceId,
      schema: start.schema,
      unknownFields: start.unknownFields,
    );
  }
}
