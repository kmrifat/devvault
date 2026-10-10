#ifndef RUNNER_APP_INSTALLER_H_
#define RUNNER_APP_INSTALLER_H_

#include <windows.h>

#include <string>

// Windows' package installer, for in-place updates of the MSIX (ADR-0007
// §4, P6-05). Its own library: C++/WinRT needs the standard library's
// exceptions, which the runner's standard settings turn off.

// Whether DevVault runs from its MSIX package (not from the zip).
bool IsRunningPackaged();

// Installs the package that the .appinstaller file at |app_installer_uri|
// describes. Windows checks its signature and publisher and closes
// DevVault; RegisterApplicationRestart asks it to start DevVault again
// (not seen on CI's runner, docs/acceptance/p6.md). Runs on a worker
// thread; when it ends without closing DevVault (a failure), posts
// |message| to |window| with the HRESULT as wParam.
void InstallFromAppInstaller(const std::wstring& app_installer_uri,
                             HWND window, UINT message);

#endif  // RUNNER_APP_INSTALLER_H_
