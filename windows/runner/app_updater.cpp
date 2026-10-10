#include "app_updater.h"

#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <string>

#include "app_installer.h"

namespace {

// UTF-8 (from Dart) to the UTF-16 Windows wants.
std::wstring Widen(const std::string& text) {
  if (text.empty()) return std::wstring();
  int length = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                   static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), length);
  return wide;
}

}  // namespace

AppUpdater::AppUpdater(flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<Channel>(
          messenger, "devvault/updater",
          &flutter::StandardMethodCodec::GetInstance())),
      window_(window) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) { Handle(call, std::move(result)); });
}

void AppUpdater::Handle(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<Result> result) {
  if (call.method_name() == "isAvailable") {
    result->Success(flutter::EncodableValue(IsRunningPackaged()));
    return;
  }
  if (call.method_name() != "install") {
    result->NotImplemented();
    return;
  }
  if (!IsRunningPackaged()) {
    result->Error("unavailable", "This copy of DevVault can't update itself.");
    return;
  }
  if (pending_) {
    result->Error("busy", "An update is already being installed.");
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const std::string* feed = nullptr;
  if (args) {
    auto it = args->find(flutter::EncodableValue("feed"));
    if (it != args->end()) feed = std::get_if<std::string>(&it->second);
  }
  if (!feed || feed->empty()) {
    result->Error("bad-arguments", "No update feed was given.");
    return;
  }
  pending_ = std::move(result);
  InstallFromAppInstaller(Widen(*feed), window_, kInstallFailed);
}

void AppUpdater::OnInstallFailed(HRESULT result) {
  if (!pending_) return;
  if (SUCCEEDED(result)) {
    // Installed without closing DevVault: it restarts on next launch.
    pending_->Success();
  } else {
    char message[96];
    std::snprintf(message, sizeof(message),
                  "Windows couldn't install the update (0x%08lX).",
                  static_cast<unsigned long>(result));
    pending_->Error("install-failed", message);
  }
  pending_.reset();
}
