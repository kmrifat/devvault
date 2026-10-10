#ifndef RUNNER_APP_UPDATER_H_
#define RUNNER_APP_UPDATER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// The `devvault/updater` channel on Windows (ADR-0007 §4, P6-05), as
// macos/Runner/AppUpdater.swift is on macOS: `isAvailable` → bool,
// `install` {feed: .appinstaller URL} → null, or an error if Windows
// couldn't install it.
class AppUpdater {
 public:
  // The window message the installer posts when it fails.
  static constexpr UINT kInstallFailed = WM_APP + 0x44;

  AppUpdater(flutter::BinaryMessenger* messenger, HWND window);

  // Answers the pending `install` with the installer's HRESULT.
  void OnInstallFailed(HRESULT result);

 private:
  using Channel = flutter::MethodChannel<flutter::EncodableValue>;
  using Result = flutter::MethodResult<flutter::EncodableValue>;

  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<Result> result);

  std::unique_ptr<Channel> channel_;
  std::unique_ptr<Result> pending_;
  HWND window_;
};

#endif  // RUNNER_APP_UPDATER_H_
