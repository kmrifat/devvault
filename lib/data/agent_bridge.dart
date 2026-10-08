import 'dart:async';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../core/agent_item_meta.dart';
import 'agent_clients.dart';
import 'providers.dart';
import 'vault_session.dart';

/// What the user answers on an agent prompt (design frame D08).
enum AgentDecision {
  allowOnce,

  /// Allow, and don't ask this client again about these items for
  /// [AgentBridgeNotifier.grantLength] (until the vault locks).
  allowForAWhile,
  deny,
}

/// A question an AI agent is waiting on. The sheet that shows it answers
/// through [AgentBridgeNotifier.answer], and closes itself when [closed]
/// completes (answered here, timed out, or the agent went away).
sealed class AgentPrompt {
  AgentPrompt({required this.id, required this.client, required this.at});

  final int id;

  /// The client's name as it introduced itself, e.g. `claude-code`.
  final String client;
  final DateTime at;

  final _answer = Completer<AgentDecision>();
  final _closed = Completer<void>();

  Future<void> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  void _close() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

/// "Allow *client* to connect to DevVault?" (P5-04).
class PairPrompt extends AgentPrompt {
  PairPrompt({required super.id, required super.client, required super.at});
}

/// A metadata read while *Allow metadata without asking* is off.
class MetadataPrompt extends AgentPrompt {
  MetadataPrompt({
    required super.id,
    required super.client,
    required super.at,
    required this.what,
  });

  /// What the agent wants to read, e.g. `items matching "acme"`.
  final String what;
}

/// One item on a [SecretPrompt]: where it sits and what is asked for.
@immutable
class SecretPromptItem {
  const SecretPromptItem({
    required this.item,
    required this.path,
    required this.names,
  });

  final Item item;

  /// app › platform › environment › title.
  final String path;

  /// Field names, attachment file names, and "Notes".
  final List<String> names;
}

/// A `request_secret` waiting for the user (P5-05).
class SecretPrompt extends AgentPrompt {
  SecretPrompt({
    required super.id,
    required super.client,
    required super.at,
    required this.reason,
    required this.delivery,
    required this.items,
  });

  /// Why the agent says it needs it, verbatim.
  final String reason;
  final Delivery delivery;
  final List<SecretPromptItem> items;
}

/// One line of the recent-activity list in Settings → AI Agents. Never
/// holds a value: titles, names, paths and the outcome only.
@immutable
class AgentActivity {
  const AgentActivity({
    required this.at,
    required this.client,
    required this.action,
    required this.detail,
    required this.outcome,
  });

  final DateTime at;
  final String client;

  /// Paired, Listed, Read, Revealed, Wrote file, Ran command.
  final String action;
  final String detail;

  /// Allowed once, Allowed for 15 minutes, Allowed earlier, Denied, …
  final String outcome;
}

/// A client waiting for the vault to be unlocked: the unlock screen shows
/// it as a banner.
@immutable
class AgentWait {
  const AgentWait({required this.client, required this.what});

  final String client;
  final String what;
}

@immutable
class AgentBridgeState {
  const AgentBridgeState({
    this.listening = false,
    this.otherInstance = false,
    this.prompts = const [],
    this.waits = const [],
    this.clients = const [],
    this.activity = const [],
  });

  /// Whether this app serves the socket right now.
  final bool listening;

  /// Agents are on, but another DevVault (another build) already serves
  /// the socket.
  final bool otherInstance;

  /// Waiting for the user, oldest first.
  final List<AgentPrompt> prompts;

  /// Requests waiting for the vault to be unlocked.
  final List<AgentWait> waits;

  final List<PairedClient> clients;

  /// Newest first, at most [AgentBridgeNotifier.activityLimit].
  final List<AgentActivity> activity;

  AgentBridgeState copyWith({
    bool? listening,
    bool? otherInstance,
    List<AgentPrompt>? prompts,
    List<AgentWait>? waits,
    List<PairedClient>? clients,
    List<AgentActivity>? activity,
  }) => AgentBridgeState(
    listening: listening ?? this.listening,
    otherInstance: otherInstance ?? this.otherInstance,
    prompts: prompts ?? this.prompts,
    waits: waits ?? this.waits,
    clients: clients ?? this.clients,
    activity: activity ?? this.activity,
  );
}

/// The app's end of the AI agent bridge (P5-03…P5-05, PROTOCOL.md):
/// serves the socket while *Settings → AI Agents* is on, answers the
/// helper's calls from the unlocked vault, and turns pairing and every
/// secret into a prompt the user answers.
///
/// Values leave only as the answer to an approved `request_secret`; they
/// are never logged or kept here.
class AgentBridgeNotifier extends Notifier<AgentBridgeState> {
  static const grantLength = Duration(minutes: 15);
  static const activityLimit = 200;

  BridgeServer? _server;
  Future<void> _serverChange = Future.value();
  var _nextPrompt = 1;

  /// `<token hash>|<item id>` → until when; `|*` for metadata. Cleared on
  /// lock.
  final Map<String, DateTime> _grants = {};
  final List<Completer<void>> _unlockWaiters = [];

  /// The prompts in [AgentBridgeState.prompts], readable while disposing.
  final List<AgentPrompt> _open = [];

  DateTime _now() => ref.read(clockProvider)();

  @override
  AgentBridgeState build() {
    ref.onDispose(() {
      _closePrompts();
      final server = _server;
      _server = null;
      server?.close();
    });
    ref.listen(
      settingsProvider.select((s) => s.agentsEnabled),
      (_, on) => _setServing(on),
    );
    ref.listen(vaultSessionProvider, (_, next) {
      if (next is Unlocked) {
        for (final waiter in _unlockWaiters.toList()) {
          if (!waiter.isCompleted) waiter.complete();
        }
      } else {
        // Nothing an agent was granted outlives the unlock.
        _grants.clear();
        _closePrompts(except: (p) => p is PairPrompt);
      }
    });
    if (ref.read(settingsProvider).agentsEnabled) {
      scheduleMicrotask(() => _setServing(true));
    }
    return AgentBridgeState(clients: ref.read(agentClientsFileProvider).load());
  }

  /// The user's answer to [prompt]. Ignored once it's closed.
  void answer(AgentPrompt prompt, AgentDecision decision) {
    if (!prompt._answer.isCompleted) prompt._answer.complete(decision);
  }

  /// Puts [prompt] in front of the user the way an agent's request does,
  /// and resolves with the answer. For tests and screenshots.
  @visibleForTesting
  Future<AgentDecision> debugAsk(AgentPrompt prompt) {
    _open.add(prompt);
    state = state.copyWith(prompts: [...state.prompts, prompt]);
    // Closed without an answer (agents off, lock, dispose) reads as deny.
    return prompt._answer.future
        .catchError((Object _) => AgentDecision.deny)
        .whenComplete(() {
          prompt._close();
          _open.remove(prompt);
          if (ref.mounted) {
            state = state.copyWith(
              prompts: [
                for (final p in state.prompts)
                  if (p != prompt) p,
              ],
            );
          }
        });
  }

  /// Shows [wait] on the unlock screen. For tests and screenshots.
  @visibleForTesting
  void debugWait(AgentWait wait) =>
      state = state.copyWith(waits: [...state.waits, wait]);

  /// Adds [entry] to the activity list. For tests and screenshots.
  @visibleForTesting
  void debugLog(AgentActivity entry) =>
      state = state.copyWith(activity: [entry, ...state.activity]);

  /// Forgets a paired client and drops its open connections.
  Future<void> revoke(PairedClient client) async {
    final clients = [
      for (final c in state.clients)
        if (c.tokenHash != client.tokenHash) c,
    ];
    state = state.copyWith(clients: clients);
    _grants.removeWhere((key, _) => key.startsWith('${client.tokenHash}|'));
    for (final session in _server?.sessions.toList() ?? <BridgeSession>[]) {
      if (session.tokenHash == client.tokenHash) session.close();
    }
    await _saveClients();
  }

  void _setServing(bool on) {
    _serverChange = _serverChange.then((_) async {
      final path = ref.read(agentSocketPathProvider);
      if (on && _server == null && path != null) {
        try {
          final server = await BridgeServer.bind(path, _handle);
          if (!ref.mounted) {
            await server?.close();
            return;
          }
          _server = server;
          state = state.copyWith(
            listening: server != null,
            otherInstance: server == null,
          );
        } on Object {
          state = state.copyWith(listening: false, otherInstance: false);
        }
      } else if (!on) {
        final server = _server;
        _server = null;
        _closePrompts();
        if (ref.mounted) {
          state = state.copyWith(listening: false, otherInstance: false);
        }
        await server?.close();
      }
    });
  }

  Future<Map<String, Object?>> _handle(BridgeCall call) async {
    final session = ref.read(vaultSessionProvider);
    switch (call.method) {
      case 'hello':
        return _hello(call, session);
      case 'status':
        return {'state': _stateOf(session).wireName};
      case 'pair':
        return _pair(call);
      case 'list':
        return _list(call);
      case 'get':
        return _get(call);
      case 'request_secret':
        return _requestSecret(call);
      default:
        throw const BridgeException(BridgeError.badRequest, 'unknown method');
    }
  }

  Map<String, Object?> _hello(BridgeCall call, VaultSession session) {
    final token = call.params['token'];
    if (token is String) {
      final hash = tokenHash(token);
      final known = state.clients.where((c) => c.tokenHash == hash);
      if (known.isNotEmpty) {
        call.session
          ..paired = true
          ..tokenHash = hash;
        _touchClient(hash);
      }
    }
    return {
      'protocol': protocolVersion,
      'app_version': '',
      'paired': call.session.paired,
      'state': _stateOf(session).wireName,
    };
  }

  Future<Map<String, Object?>> _pair(BridgeCall call) async {
    final client = ClientInfo.fromJson(call.params['client']);
    // Pairing is a security decision: the person approving it has to be
    // able to open the vault.
    await _whenUnlocked(call, 'to connect');
    final prompt = PairPrompt(
      id: _nextPrompt++,
      client: client.name,
      at: _now(),
    );
    final decision = await _ask(call, prompt, 'Paired', 'this device');
    if (decision == AgentDecision.deny) {
      throw const BridgeException(BridgeError.denied);
    }
    final token = newPairingToken();
    final hash = tokenHash(token);
    state = state.copyWith(
      clients: [
        ...state.clients,
        PairedClient(
          tokenHash: hash,
          name: client.name,
          pairedAt: _now(),
          lastSeen: _now(),
        ),
      ],
    );
    await _saveClients();
    call.session
      ..paired = true
      ..tokenHash = hash;
    return {'token': token};
  }

  Future<Map<String, Object?>> _list(BridgeCall call) async {
    final p = call.params;
    String? text(String key) {
      final value = p[key];
      if (value == null) return null;
      if (value is! String) {
        throw BridgeException(BridgeError.badRequest, key);
      }
      return value;
    }

    final query = text('query'), app = text('app'), type = text('type');
    final what = query == null ? 'the item list' : 'items matching "$query"';
    final index = await _readMetadata(call, 'Listed', what);
    final appIds = app == null
        ? null
        : {
            for (final record in index.apps.values)
              if (record.id == app ||
                  record.name.toLowerCase() == app.toLowerCase())
                record.id,
          };
    final items = [
      for (final item in index.filter(
        platform: text('platform'),
        environment: text('environment'),
        tag: text('tag'),
        query: query,
      ))
        if ((appIds == null || appIds.contains(item.appId)) &&
            (type == null || item.typeName == type))
          agentItemMeta(item, index.apps[item.appId]),
    ];
    return {'items': items};
  }

  Future<Map<String, Object?>> _get(BridgeCall call) async {
    final id = call.params['id'];
    if (id is! String) {
      throw const BridgeException(BridgeError.badRequest, 'id');
    }
    final index = await _readMetadata(call, 'Read', 'an item');
    final item = index.items[id];
    if (item == null) throw BridgeException(BridgeError.notFound, id);
    return {'item': agentItemMeta(item, index.apps[item.appId])};
  }

  /// The unlocked index, after asking when metadata needs approval.
  Future<VaultIndex> _readMetadata(
    BridgeCall call,
    String action,
    String what,
  ) async {
    var index = (await _whenUnlocked(call, 'to read $what')).index;
    final key = '${call.session.tokenHash}|*';
    if (ref.read(settingsProvider).agentMetadataWithoutAsking) {
      _log(call, action, what, 'Allowed without asking');
      return index;
    }
    if (_granted([key])) {
      _log(call, action, what, 'Allowed earlier');
      return index;
    }
    final prompt = MetadataPrompt(
      id: _nextPrompt++,
      client: call.session.client!.name,
      at: _now(),
      what: what,
    );
    final decision = await _ask(call, prompt, action, what);
    if (decision == AgentDecision.deny) {
      throw const BridgeException(BridgeError.denied);
    }
    if (decision == AgentDecision.allowForAWhile) _grant([key]);
    index = (await _whenUnlocked(call, 'to read $what')).index;
    return index;
  }

  Future<Map<String, Object?>> _requestSecret(BridgeCall call) async {
    final request = SecretRequest.fromJson(call.params);
    var unlocked = await _whenUnlocked(call, 'for a secret');
    // Checks everything named before asking: a typo never reaches the user.
    final items = _resolve(unlocked.index, request);
    final action = switch (request.delivery.mode) {
      DeliveryMode.reveal => 'Revealed',
      DeliveryMode.file => 'Wrote file',
      DeliveryMode.command => 'Ran command',
    };
    final detail = items.map((i) => i.item.title).join(', ');
    final keys = [
      for (final i in items) '${call.session.tokenHash}|${i.item.id}',
    ];
    if (_granted(keys)) {
      _log(call, action, detail, 'Allowed earlier');
    } else {
      final prompt = SecretPrompt(
        id: _nextPrompt++,
        client: call.session.client!.name,
        at: _now(),
        reason: request.reason,
        delivery: request.delivery,
        items: items,
      );
      final decision = await _ask(call, prompt, action, detail);
      if (decision == AgentDecision.deny) {
        throw const BridgeException(BridgeError.denied);
      }
      if (decision == AgentDecision.allowForAWhile) _grant(keys);
    }
    // Locking while the sheet was open closes it; anything after that
    // reads the vault as it is now.
    final session = ref.read(vaultSessionProvider);
    if (session is! Unlocked) {
      throw const BridgeException(BridgeError.denied, 'The vault locked');
    }
    unlocked = session;
    final result = <SecretItem>[];
    for (final (i, wanted) in request.items.indexed) {
      final item = unlocked.index.items[wanted.id] ?? items[i].item;
      result.add(
        SecretItem(
          id: item.id,
          fields: {
            for (final MapEntry(:key, :value) in item.fields.entries)
              if (wanted.wantsAllFields ||
                  (wanted.fields?.contains(key) ?? false))
                key: value.value,
          },
          attachments: [
            for (final a in item.attachments)
              if (wanted.attachments?.contains(a.blobId) ?? false)
                SecretAttachment(
                  id: a.blobId,
                  filename: a.filename,
                  mime: a.mime,
                  data: await unlocked.vault.readAttachment(a),
                ),
          ],
          notes: wanted.notes ? item.notes : null,
        ),
      );
    }
    return SecretResult(result).toJson();
  }

  /// The items a request names, with what it asks of each. Throws
  /// `not_found` naming only the id or name that's missing.
  List<SecretPromptItem> _resolve(VaultIndex index, SecretRequest request) => [
    for (final wanted in request.items)
      () {
        final item = index.items[wanted.id];
        if (item == null) {
          throw BridgeException(BridgeError.notFound, wanted.id);
        }
        for (final name in wanted.fields ?? const <String>[]) {
          if (!item.fields.containsKey(name)) {
            throw BridgeException(BridgeError.notFound, 'field $name');
          }
        }
        final files = {for (final a in item.attachments) a.blobId: a};
        for (final id in wanted.attachments ?? const <String>[]) {
          if (!files.containsKey(id)) {
            throw BridgeException(BridgeError.notFound, 'attachment $id');
          }
        }
        if (wanted.notes && (item.notes?.isEmpty ?? true)) {
          throw const BridgeException(BridgeError.notFound, 'notes');
        }
        return SecretPromptItem(
          item: item,
          path: agentItemPath(item, index.apps[item.appId]),
          names: [
            if (wanted.wantsAllFields)
              ...item.fields.keys
            else
              ...?wanted.fields,
            for (final id in wanted.attachments ?? const <String>[])
              files[id]!.filename,
            if (wanted.notes) 'Notes',
          ],
        );
      }(),
  ];

  /// The unlocked session; waits (with a banner on the unlock screen) when
  /// the vault is locked.
  Future<Unlocked> _whenUnlocked(BridgeCall call, String what) async {
    var session = ref.read(vaultSessionProvider);
    if (session is Unlocked) return session;
    if (session is NoVault) throw const BridgeException(BridgeError.noVault);
    final wait = AgentWait(client: call.session.client!.name, what: what);
    final waiter = Completer<void>();
    _unlockWaiters.add(waiter);
    state = state.copyWith(waits: [...state.waits, wait]);
    unawaited(ref.read(bringToFrontProvider)());
    try {
      await _race(call, waiter.future);
    } finally {
      _unlockWaiters.remove(waiter);
      if (ref.mounted) {
        state = state.copyWith(
          waits: [
            for (final w in state.waits)
              if (!identical(w, wait)) w,
          ],
        );
      }
    }
    session = ref.read(vaultSessionProvider);
    if (session is! Unlocked) throw const BridgeException(BridgeError.timeout);
    return session;
  }

  /// Shows [prompt] and waits for the answer; logs the outcome.
  Future<AgentDecision> _ask(
    BridgeCall call,
    AgentPrompt prompt,
    String action,
    String detail,
  ) async {
    _open.add(prompt);
    state = state.copyWith(prompts: [...state.prompts, prompt]);
    unawaited(ref.read(bringToFrontProvider)());
    try {
      final decision = await _race(call, prompt._answer.future);
      _log(call, action, detail, switch (decision) {
        AgentDecision.allowOnce => 'Allowed once',
        AgentDecision.allowForAWhile => 'Allowed for 15 minutes',
        AgentDecision.deny => 'Denied',
      }, client: prompt.client);
      return decision;
    } on BridgeException catch (e) {
      _log(call, action, detail, switch (e.code) {
        BridgeError.timeout => 'No answer',
        BridgeError.disabled => 'AI agents turned off',
        BridgeError.denied => 'Vault locked',
        _ => 'Cancelled',
      }, client: prompt.client);
      rethrow;
    } finally {
      prompt._close();
      _open.remove(prompt);
      if (ref.mounted) {
        state = state.copyWith(
          prompts: [
            for (final p in state.prompts)
              if (p != prompt) p,
          ],
        );
      }
    }
  }

  /// [future], unless the agent hangs up, the user doesn't answer in time
  /// or agents are turned off.
  Future<T> _race<T>(BridgeCall call, Future<T> future) async {
    final timeout = ref.read(agentTimeoutProvider);
    final gone = call.session.closed.then<T>(
      (_) => throw const BridgeException(BridgeError.internal, 'closed'),
    );
    try {
      return await Future.any([future, gone]).timeout(
        timeout,
        onTimeout: () => throw const BridgeException(BridgeError.timeout),
      );
    } on _Disabled {
      throw const BridgeException(BridgeError.disabled);
    } on _Locked {
      throw const BridgeException(BridgeError.denied, 'The vault locked');
    }
  }

  /// Closes the open prompts (agents turned off, or the vault locked) and
  /// fails what waits on them.
  void _closePrompts({bool Function(AgentPrompt)? except}) {
    final disabling = except == null;
    for (final prompt in _open.toList()) {
      if (except != null && except(prompt)) continue;
      if (!prompt._answer.isCompleted) {
        prompt._answer.completeError(disabling ? _Disabled() : _Locked());
      }
      prompt._close();
    }
    if (disabling) {
      for (final waiter in _unlockWaiters.toList()) {
        if (!waiter.isCompleted) waiter.completeError(_Disabled());
      }
    }
  }

  bool _granted(List<String> keys) {
    final now = _now();
    _grants.removeWhere((_, until) => !until.isAfter(now));
    return keys.every(_grants.containsKey);
  }

  void _grant(List<String> keys) {
    final until = _now().add(grantLength);
    for (final key in keys) {
      _grants[key] = until;
    }
  }

  void _log(
    BridgeCall call,
    String action,
    String detail,
    String outcome, {
    String? client,
  }) {
    if (!ref.mounted) return;
    final entry = AgentActivity(
      at: _now(),
      client: client ?? call.session.client?.name ?? '',
      action: action,
      detail: detail,
      outcome: outcome,
    );
    state = state.copyWith(
      activity: [entry, ...state.activity.take(activityLimit - 1)],
    );
  }

  void _touchClient(String hash) {
    state = state.copyWith(
      clients: [
        for (final c in state.clients)
          c.tokenHash == hash ? c.seenAt(_now()) : c,
      ],
    );
    unawaited(_saveClients());
  }

  Future<void> _saving = Future.value();

  Future<void> _saveClients() {
    final clients = state.clients;
    final file = ref.read(agentClientsFileProvider);
    // Best effort, one after another: a failed write only means the
    // client pairs again next launch.
    return _saving = _saving
        .then((_) => file.save(clients))
        .catchError((Object _) {});
  }

  static VaultState _stateOf(VaultSession session) => switch (session) {
    NoVault() => VaultState.noVault,
    Locked() => VaultState.locked,
    Unlocked() => VaultState.unlocked,
  };
}

class _Disabled implements Exception {}

class _Locked implements Exception {}

final agentBridgeProvider =
    NotifierProvider<AgentBridgeNotifier, AgentBridgeState>(
      AgentBridgeNotifier.new,
    );
