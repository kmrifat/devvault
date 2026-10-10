#include "app_installer.h"

#include <appmodel.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Management.Deployment.h>

#include <thread>

namespace deployment = winrt::Windows::Management::Deployment;

bool IsRunningPackaged() {
  UINT32 length = 0;
  return GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

void InstallFromAppInstaller(const std::wstring& app_installer_uri,
                             HWND window, UINT message) {
  // Windows closes DevVault to replace it; this brings it back afterwards.
  RegisterApplicationRestart(nullptr, 0);
  std::thread([app_installer_uri, window, message]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    HRESULT result = S_OK;
    try {
      deployment::PackageManager manager;
      auto outcome =
          manager
              .AddPackageByAppInstallerFileAsync(
                  winrt::Windows::Foundation::Uri(app_installer_uri),
                  deployment::AddPackageByAppInstallerOptions::
                      ForceTargetAppShutdown,
                  nullptr)
              .get();
      result = outcome.ExtendedErrorCode();
    } catch (winrt::hresult_error const& error) {
      result = error.code();
    }
    PostMessage(window, message, static_cast<WPARAM>(result), 0);
    winrt::uninit_apartment();
  }).detach();
}
