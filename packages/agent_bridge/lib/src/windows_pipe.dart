import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'channel.dart';

/// The bridge on Windows (P5-11, PROTOCOL.md §1): a named pipe, as Dart has
/// no Unix sockets there.
///
/// - The pipe is `\\.\pipe\devvault-<user SID>` ([pipeNameForCurrentUser]):
///   the pipe namespace is shared by every user on the machine.
/// - Its DACL grants the current user alone, and nobody else, not even
///   administrators; remote clients are rejected; the app only serves a
///   name it created first, so another DevVault already serving it wins.
/// - The helper connects at identification level, so the app can't act as
///   it, and checks that the process serving the pipe runs as the same
///   user: a pipe someone else made under that name is refused.
///
/// The I/O is overlapped and polled from a timer on the calling isolate,
/// so nothing blocks it; a connection's buffers live until the system has
/// let go of them.

/// The pipe for the user this process runs as.
String pipeNameForCurrentUser() => '\\\\.\\pipe\\devvault-${currentUserSid()}';

/// The current process's user, as a SID string (`S-1-5-21-…`).
String currentUserSid() => _tokenUserSid(_getCurrentProcess());

/// Starts serving [name], or returns null when another process already
/// does.
Future<BridgeListener?> bindPipe(String name) async => _PipeListener.bind(name);

/// Connects to the app's pipe [name]. Throws [PipeException] when nothing
/// serves it, or when what serves it isn't the current user's.
Future<BridgeChannel> connectPipe(String name, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  final path = name.toNativeUtf16();
  try {
    while (true) {
      final handle = _createFileW(
        path,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        _fileFlagOverlapped | _securitySqosPresent | _securityIdentification,
        nullptr,
      );
      final error = _getLastError();
      if (!_invalid(handle)) {
        try {
          _checkServerIsCurrentUser(handle);
        } on Object {
          _closeHandle(handle);
          rethrow;
        }
        return _PipeChannel(handle, server: false);
      }
      // Every instance is taken: one frees up when its client goes.
      if (error == _errorPipeBusy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      throw PipeException('connect', error);
    }
  } finally {
    calloc.free(path);
  }
}

/// A named-pipe call failed with Windows error [code].
class PipeException implements IOException {
  const PipeException(this.operation, this.code);

  final String operation;
  final int code;

  @override
  String toString() => 'PipeException($operation, $code)';
}

void _checkServerIsCurrentUser(Pointer<Void> pipe) {
  final pid = calloc<Uint32>();
  try {
    if (_getNamedPipeServerProcessId(pipe, pid) == 0) {
      throw PipeException('server process', _getLastError());
    }
    final process = _openProcess(_processQueryLimitedInformation, 0, pid.value);
    if (_invalid(process) || process == nullptr) {
      throw PipeException('open server process', _getLastError());
    }
    try {
      if (_tokenUserSid(process) != currentUserSid()) {
        throw const PipeException('server is another user', 0);
      }
    } finally {
      _closeHandle(process);
    }
  } finally {
    calloc.free(pid);
  }
}

/// The SID of the user [process] runs as.
String _tokenUserSid(Pointer<Void> process) {
  final token = calloc<Pointer<Void>>();
  final size = calloc<Uint32>();
  final text = calloc<Pointer<Utf16>>();
  Pointer<Uint8> info = nullptr;
  try {
    if (_openProcessToken(process, _tokenQuery, token) == 0) {
      throw PipeException('open token', _getLastError());
    }
    try {
      // First call: how big TOKEN_USER is.
      _getTokenInformation(token.value, _tokenUser, nullptr, 0, size);
      info = calloc<Uint8>(size.value);
      if (_getTokenInformation(
            token.value,
            _tokenUser,
            info.cast(),
            size.value,
            size,
          ) ==
          0) {
        throw PipeException('token user', _getLastError());
      }
      // TOKEN_USER starts with SID_AND_ATTRIBUTES, which starts with the
      // SID's pointer.
      final sid = info.cast<Pointer<Void>>().value;
      if (_convertSidToStringSidW(sid, text) == 0) {
        throw PipeException('sid to string', _getLastError());
      }
      try {
        return text.value.toDartString();
      } finally {
        _localFree(text.value.cast());
      }
    } finally {
      _closeHandle(token.value);
    }
  } finally {
    if (info != nullptr) calloc.free(info);
    calloc
      ..free(token)
      ..free(size)
      ..free(text);
  }
}

/// SECURITY_ATTRIBUTES holding a DACL that grants [sid] alone.
class _OwnerOnly {
  _OwnerOnly(String sid) {
    final sddl = 'D:P(A;;GA;;;$sid)'.toNativeUtf16();
    final descriptor = calloc<Pointer<Void>>();
    try {
      if (_convertStringSecurityDescriptorToSecurityDescriptorW(
            sddl,
            _sddlRevision1,
            descriptor,
            nullptr,
          ) ==
          0) {
        throw PipeException('security descriptor', _getLastError());
      }
      _descriptor = descriptor.value;
    } finally {
      calloc
        ..free(sddl)
        ..free(descriptor);
    }
    attributes = calloc<_SecurityAttributes>()
      ..ref.nLength = sizeOf<_SecurityAttributes>()
      ..ref.lpSecurityDescriptor = _descriptor
      ..ref.bInheritHandle = 0;
  }

  late final Pointer<Void> _descriptor;
  late final Pointer<_SecurityAttributes> attributes;

  void free() {
    calloc.free(attributes);
    _localFree(_descriptor);
  }
}

class _PipeListener implements BridgeListener {
  _PipeListener._(this._name, this._security);

  static _PipeListener? bind(String name) {
    final listener = _PipeListener._(
      name.toNativeUtf16(),
      _OwnerOnly(currentUserSid()),
    );
    if (!listener._listen(first: true)) {
      listener._release();
      return null;
    }
    return listener;
  }

  final Pointer<Utf16> _name;
  final _OwnerOnly _security;
  final _connections = StreamController<BridgeChannel>();
  _Pending? _waiting;
  Timer? _timer;
  var _closed = false;

  @override
  Stream<BridgeChannel> get connections => _connections.stream;

  /// Makes the next instance and waits for a client on it. [first]: the
  /// name must not exist yet (another DevVault serves it, or someone else
  /// made it).
  bool _listen({bool first = false}) {
    final handle = _createNamedPipeW(
      _name,
      _pipeAccessDuplex |
          _fileFlagOverlapped |
          (first ? _fileFlagFirstPipeInstance : 0),
      _pipeTypeByte | _pipeReadmodeByte | _pipeWait | _pipeRejectRemoteClients,
      _pipeUnlimitedInstances,
      _bufferSize,
      _bufferSize,
      0,
      _security.attributes,
    );
    if (_invalid(handle)) return false;
    final pending = _Pending(handle);
    final connected = _connectNamedPipe(handle, pending.overlapped);
    final error = _getLastError();
    if (connected != 0 || error == _errorPipeConnected) {
      // A client came between creating and waiting.
      pending.releaseEvent();
      _accept(handle);
      return _listen();
    }
    if (error != _errorIoPending) {
      pending.releaseEvent();
      _closeHandle(handle);
      return false;
    }
    _waiting = pending;
    _timer ??= Timer.periodic(_pollEvery, (_) => _poll());
    return true;
  }

  void _poll() {
    final waiting = _waiting;
    if (waiting == null || !waiting.isSignalled) return;
    _waiting = null;
    final ok = waiting.finish();
    waiting.releaseEvent();
    if (ok) {
      _accept(waiting.handle);
    } else {
      _closeHandle(waiting.handle);
    }
    if (!_closed) _listen();
  }

  void _accept(Pointer<Void> handle) {
    if (_closed) {
      _closeHandle(handle);
    } else {
      _connections.add(_PipeChannel(handle, server: true));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null) {
      _cancelIoEx(waiting.handle, waiting.overlapped);
      waiting
        ..finish(wait: true)
        ..releaseEvent();
      _closeHandle(waiting.handle);
    }
    _release();
    await _connections.close();
  }

  void _release() {
    calloc.free(_name);
    _security.free();
  }
}

/// An overlapped operation on [handle] and the event it signals.
class _Pending {
  _Pending(this.handle) {
    final event = _createEventW(nullptr, 1, 0, nullptr);
    if (_invalid(event) || event == nullptr) {
      throw PipeException('event', _getLastError());
    }
    overlapped = calloc<_Overlapped>()..ref.hEvent = event;
  }

  final Pointer<Void> handle;
  late final Pointer<_Overlapped> overlapped;
  final transferred = calloc<Uint32>();

  bool get isSignalled =>
      _waitForSingleObject(overlapped.ref.hEvent, 0) == _waitObject0;

  /// Whether it succeeded; [transferred] says how many bytes moved.
  bool finish({bool wait = false}) =>
      _getOverlappedResult(handle, overlapped, transferred, wait ? 1 : 0) != 0;

  void releaseEvent() {
    _closeHandle(overlapped.ref.hEvent);
    calloc
      ..free(overlapped)
      ..free(transferred);
  }
}

class _PipeChannel implements BridgeChannel {
  _PipeChannel(this._handle, {required this.server})
    : _read = _Pending(_handle),
      _write = _Pending(_handle) {
    _startRead();
    _timer = Timer.periodic(_pollEvery, (_) => _poll());
  }

  final Pointer<Void> _handle;

  /// Whether this is the app's end, which disconnects the instance.
  final bool server;
  final _Pending _read;
  final _Pending _write;
  final _readBuffer = calloc<Uint8>(_bufferSize);
  Pointer<Uint8> _writeBuffer = nullptr;
  final _queue = <List<int>>[];
  final _input = StreamController<List<int>>();
  final _done = Completer<void>();
  late final Timer _timer;
  var _reading = false;
  var _writing = false;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void add(List<int> bytes) {
    if (_done.isCompleted) throw StateError('The pipe is closed');
    if (bytes.isEmpty) return;
    _queue.add(bytes);
    _startWrite();
  }

  @override
  void destroy() {
    if (_done.isCompleted) return;
    _timer.cancel();
    // Nothing may still write into the buffers once they're freed.
    _cancelIoEx(_handle, nullptr);
    if (_reading) _read.finish(wait: true);
    if (_writing) _write.finish(wait: true);
    if (server) _disconnectNamedPipe(_handle);
    _closeHandle(_handle);
    _read.releaseEvent();
    _write.releaseEvent();
    calloc.free(_readBuffer);
    if (_writeBuffer != nullptr) calloc.free(_writeBuffer);
    _writeBuffer = nullptr;
    _queue.clear();
    unawaited(_input.close());
    _done.complete();
  }

  void _startRead() {
    final ok = _readFile(
      _handle,
      _readBuffer,
      _bufferSize,
      nullptr,
      _read.overlapped,
    );
    final error = _getLastError();
    // Done at once or later: either way the event says when.
    if (ok != 0 || error == _errorIoPending) {
      _reading = true;
    } else {
      destroy();
    }
  }

  void _startWrite() {
    if (_writing || _queue.isEmpty || _done.isCompleted) return;
    final bytes = _queue.removeAt(0);
    _writeBuffer = calloc<Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    final ok = _writeFile(
      _handle,
      _writeBuffer,
      bytes.length,
      nullptr,
      _write.overlapped,
    );
    final error = _getLastError();
    if (ok != 0 || error == _errorIoPending) {
      _writing = true;
    } else {
      destroy();
    }
  }

  void _poll() {
    if (_done.isCompleted) return;
    if (_reading && _read.isSignalled) {
      _reading = false;
      if (!_read.finish()) return destroy();
      final count = _read.transferred.value;
      if (count > 0) {
        _input.add(Uint8List.fromList(_readBuffer.asTypedList(count)));
      }
      _startRead();
    }
    if (_writing && _write.isSignalled) {
      _writing = false;
      final ok = _write.finish();
      calloc.free(_writeBuffer);
      _writeBuffer = nullptr;
      if (!ok) return destroy();
      _startWrite();
    }
  }
}

// Win32 (kernel32 and advapi32). GetLastError is looked up first, so that
// reading it right after a call doesn't run a lookup that could reset it.

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');

const _bufferSize = 64 * 1024;
const _pollEvery = Duration(milliseconds: 10);

const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _openExisting = 3;
const _fileFlagOverlapped = 0x40000000;
const _fileFlagFirstPipeInstance = 0x00080000;
const _securitySqosPresent = 0x00100000;
const _securityIdentification = 0x00010000;
const _pipeAccessDuplex = 0x3;
const _pipeTypeByte = 0x0;
const _pipeReadmodeByte = 0x0;
const _pipeWait = 0x0;
const _pipeRejectRemoteClients = 0x8;
const _pipeUnlimitedInstances = 255;
const _processQueryLimitedInformation = 0x1000;
const _tokenQuery = 0x0008;
const _tokenUser = 1;
const _sddlRevision1 = 1;
const _waitObject0 = 0;
const _errorIoPending = 997;
const _errorPipeConnected = 535;
const _errorPipeBusy = 231;

bool _invalid(Pointer<Void> handle) => handle.address == -1;

final class _Overlapped extends Struct {
  @IntPtr()
  external int internal;
  @IntPtr()
  external int internalHigh;
  @Uint32()
  external int offset;
  @Uint32()
  external int offsetHigh;
  external Pointer<Void> hEvent;
}

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;
  external Pointer<Void> lpSecurityDescriptor;
  @Int32()
  external int bInheritHandle;
}

final int Function() _getLastError = (() {
  final f = _kernel32.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  f();
  return f;
})();

final _getCurrentProcess = _kernel32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetCurrentProcess',
    );

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CloseHandle',
    );

final _localFree = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');

final _createNamedPipeW = _kernel32
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Pointer<_SecurityAttributes>,
      ),
      Pointer<Void> Function(
        Pointer<Utf16>,
        int,
        int,
        int,
        int,
        int,
        int,
        Pointer<_SecurityAttributes>,
      )
    >('CreateNamedPipeW');

final _connectNamedPipe = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<_Overlapped>),
      int Function(Pointer<Void>, Pointer<_Overlapped>)
    >('ConnectNamedPipe');

final _disconnectNamedPipe = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'DisconnectNamedPipe',
    );

final _getNamedPipeServerProcessId = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)
    >('GetNamedPipeServerProcessId');

final _createFileW = _kernel32
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        Pointer<Void>,
      ),
      Pointer<Void> Function(
        Pointer<Utf16>,
        int,
        int,
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
      )
    >('CreateFileW');

final _readFile = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      )
    >('ReadFile');

final _writeFile = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      )
    >('WriteFile');

final _getOverlappedResult = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<_Overlapped>,
        Pointer<Uint32>,
        Int32,
      ),
      int Function(Pointer<Void>, Pointer<_Overlapped>, Pointer<Uint32>, int)
    >('GetOverlappedResult');

final _cancelIoEx = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<_Overlapped>),
      int Function(Pointer<Void>, Pointer<_Overlapped>)
    >('CancelIoEx');

final _createEventW = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Int32, Int32, Pointer<Utf16>),
      Pointer<Void> Function(Pointer<Void>, int, int, Pointer<Utf16>)
    >('CreateEventW');

final _waitForSingleObject = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('WaitForSingleObject');

final _openProcess = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Uint32),
      Pointer<Void> Function(int, int, int)
    >('OpenProcess');

final _openProcessToken = _advapi32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
    >('OpenProcessToken');

final _getTokenInformation = _advapi32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Int32,
        Pointer<Void>,
        Uint32,
        Pointer<Uint32>,
      ),
      int Function(Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>)
    >('GetTokenInformation');

final _convertSidToStringSidW = _advapi32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>),
      int Function(Pointer<Void>, Pointer<Pointer<Utf16>>)
    >('ConvertSidToStringSidW');

final _convertStringSecurityDescriptorToSecurityDescriptorW = _advapi32
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Uint32,
        Pointer<Pointer<Void>>,
        Pointer<Uint32>,
      ),
      int Function(Pointer<Utf16>, int, Pointer<Pointer<Void>>, Pointer<Uint32>)
    >('ConvertStringSecurityDescriptorToSecurityDescriptorW');
