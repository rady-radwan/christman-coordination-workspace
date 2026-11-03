"""Patches the generated Windows runner (windows/runner/main.cpp) after `flutter create`.

If the app is already open and a sign-in link is clicked, Windows starts a
second copy. This hands the link to the open window instead and brings it to the
front (pattern from the app_links package README).
"""
import pathlib
import sys

TITLE = "Christman Coordination Workspace"
path = pathlib.Path("windows/runner/main.cpp")
src = path.read_text(encoding="utf-8")

if "SendAppLinkToInstance" in src:
    print("main.cpp already patched")
    sys.exit(0)

helper = r'''#include "app_links/app_links_plugin_c_api.h"

// Sends a clicked link to an already-open app window, if there is one.
bool SendAppLinkToInstance(const std::wstring& title) {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());
  if (hwnd) {
    SendAppLink(hwnd);
    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &place);
    switch (place.showCmd) {
      case SW_SHOWMAXIMIZED:
        ShowWindow(hwnd, SW_SHOWMAXIMIZED);
        break;
      case SW_SHOWMINIMIZED:
        ShowWindow(hwnd, SW_RESTORE);
        break;
      default:
        ShowWindow(hwnd, SW_NORMAL);
        break;
    }
    SetWindowPos(0, HWND_TOP, 0, 0, 0, 0, SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    SetForegroundWindow(hwnd);
    return true;
  }
  return false;
}
'''

anchor = '#include "utils.h"'
if anchor not in src:
    sys.exit("could not find utils.h include in main.cpp")
src = src.replace(anchor, anchor + "\n\n" + helper, 1)

marker = "_In_ int show_command) {"
if marker not in src:
    sys.exit("could not find wWinMain in main.cpp")
src = src.replace(
    marker,
    marker + '\n  if (SendAppLinkToInstance(L"' + TITLE + '")) {\n    return EXIT_SUCCESS;\n  }\n',
    1,
)
path.write_text(src, encoding="utf-8")
print("main.cpp patched for app links")
