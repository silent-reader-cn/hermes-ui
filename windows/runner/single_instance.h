#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// Single-instance guard for HermesUI (project requirement: no duplicate
// instances; second launch must surface and focus the first window).
//
// Mechanism: a named mutex is created at process start. If creation reports
// ERROR_ALREADY_EXISTS another instance is already running; the new process
// broadcasts a registered window message that the first instance maps to
// "restore + foreground" and then exits immediately.
//
// The mutex is owned by the kernel and released automatically when the first
// instance exits, including on crash, so no stale-lock cleanup is needed.

// Custom message broadcast to the running instance. Registered at runtime to
// avoid collisions with WM_APP ranges used by Flutter or plugins.
inline UINT HermesSingleInstanceMessage() {
  static const UINT msg = ::RegisterWindowMessageW(L"HermesUI.SingleInstance.Activate");
  return msg;
}

inline const wchar_t* HermesSingleInstanceMutexName() {
  return L"Local\\HermesUI.SingleInstance.Mutex";
}

// Returns true when this process is the single allowed instance. Otherwise a
// broadcast was delivered to the running instance and the caller must exit
// without creating any window.
inline bool HermesAcquireSingleInstanceLock() {
  // Allow the already-running instance to take foreground when we broadcast.
  // (Documented pattern: the second process is not foreground, so it grants
  // its "foreground rights" to the first instance's PID.)
  const HANDLE mutex = ::CreateMutexW(nullptr, TRUE, HermesSingleInstanceMutexName());
  if (mutex != nullptr && ::GetLastError() != ERROR_ALREADY_EXISTS) {
    // We own the mutex. Intentionally never released: kernel closes it when
    // the process exits.
    return true;
  }
  if (mutex != nullptr) {
    ::CloseHandle(mutex);
  }

  // Notify the running instance to show + focus its window.
  ::AllowSetForegroundWindow(ASFW_ANY);
  ::PostMessageW(HWND_BROADCAST, HermesSingleInstanceMessage(), 0, 0);
  return false;
}

#endif  // RUNNER_SINGLE_INSTANCE_H_
