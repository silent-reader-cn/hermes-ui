#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "single_instance.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    default:
      // Single-instance activate request (broadcast from a second launch):
      // restore the window if minimized/hidden, then bring it to the
      // foreground. Registered message value is dynamic, so compare via the
      // accessor instead of a case label.
      if (message == HermesSingleInstanceMessage()) {
        HWND self = GetHandle();
        if (self != nullptr) {
          // Recover minimized or hidden windows (e.g. tray-minimized state).
          WINDOWPLACEMENT placement = {};
          placement.length = sizeof(placement);
          if (::GetWindowPlacement(self, &placement) &&
              (placement.showCmd == SW_SHOWMINIMIZED ||
               placement.showCmd == SW_SHOWMINNOACTIVE)) {
            ::ShowWindow(self, SW_RESTORE);
          }
          if (!::IsWindowVisible(self)) {
            ::ShowWindow(self, SW_SHOW);
          }
          ::SetForegroundWindow(self);
          // If the OS denied foreground rights, flash the taskbar button so
          // the activation attempt is still visible to the user.
          FLASHWINFO flash = {};
          flash.cbSize = sizeof(flash);
          flash.hwnd = self;
          flash.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
          flash.uCount = 3;
          flash.dwTimeout = 0;
          ::FlashWindowEx(&flash);
        }
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
