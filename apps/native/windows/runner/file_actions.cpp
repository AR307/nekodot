#include "file_actions.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <algorithm>
#include <cwctype>
#include <string>

namespace {

// Types that run code when "opened". AssocIsDangerous covers the system's own list
// (and FTA_AlwaysUnsafe registrations); these extensions are refused even where a
// machine's registry is incomplete.
constexpr const wchar_t* kAlwaysUnsafe[] = {
    L".appref-ms", L".bat", L".chm", L".cmd", L".com", L".cpl", L".diagcab",
    L".exe", L".hta", L".inf", L".jar", L".js", L".jse", L".library-ms", L".lnk",
    L".msc", L".msi", L".msix", L".msixbundle", L".msp", L".appx", L".appxbundle",
    L".pif", L".ps1", L".psm1", L".reg", L".scf", L".scr", L".settingcontent-ms",
    L".sys", L".url", L".vb", L".vbe", L".vbs", L".ws", L".wsc", L".wsf", L".wsh"};

bool IsExecutable(const std::wstring& path) {
  std::wstring extension = PathFindExtensionW(path.c_str());
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  if (extension.empty()) return false;
  if (AssocIsDangerous(extension.c_str())) return true;
  return std::any_of(std::begin(kAlwaysUnsafe), std::end(kAlwaysUnsafe),
                     [&](const wchar_t* unsafe) { return extension == unsafe; });
}

// Mark of the Web: the copy came from a bot, i.e. the internet zone, so Windows keeps
// SmartScreen, Protected View and macro blocking on every route that opens it later.
bool MarkFromInternet(const std::wstring& path) {
  const std::wstring stream = path + L":Zone.Identifier";
  const HANDLE handle = CreateFileW(stream.c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;
  static constexpr char kZone[] = "[ZoneTransfer]\r\nZoneId=3\r\n";
  DWORD written = 0;
  const BOOL ok = WriteFile(handle, kZone, sizeof(kZone) - 1, &written, nullptr);
  CloseHandle(handle);
  return ok && written == sizeof(kZone) - 1;
}

}  // namespace

void RegisterFileActions(flutter::BinaryMessenger* messenger, HWND window) {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "app.nekodot/files", &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([window](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method != "open" && method != "openWith" && method != "reveal") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const auto item = args ? args->find(flutter::EncodableValue("path"))
                           : flutter::EncodableMap::const_iterator{};
    const auto* path = args && item != args->end()
                           ? std::get_if<std::string>(&item->second) : nullptr;
    if (!path || path->empty() || path->size() > 32760 ||
        path->find('\0') != std::string::npos) {
      result->Error("invalid_path", "Expected an absolute file path.");
      return;
    }
    const auto length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        path->data(), static_cast<int>(path->size()), nullptr, 0);
    std::wstring wide(length, L'\0');
    if (length == 0 || MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        path->data(), static_cast<int>(path->size()), wide.data(), length) == 0 ||
        PathIsRelativeW(wide.c_str())) {
      result->Error("invalid_path", "Expected an absolute UTF-8 file path.");
      return;
    }
    const auto attributes = GetFileAttributesW(wide.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
      result->Error("file_unavailable", "The preview copy is unavailable.");
      return;
    }
    if (!MarkFromInternet(wide)) {
      result->Error("unprotected", "The preview copy could not be marked as downloaded.");
      return;
    }
    // A bot-delivered program or script is never run by a plain "open"; the person can
    // still reveal it or explicitly choose an app with "open with".
    if (method == "open" && IsExecutable(wide)) {
      result->Error("blocked_type", "Executable files are not opened directly.");
      return;
    }
    HRESULT status = S_OK;
    if (method == "openWith") {
      OPENASINFO info{};
      info.pcszFile = wide.c_str();
      // Open the selected copy without changing the user's default association.
      info.oaifInFlags = OAIF_EXEC;
      status = SHOpenWithDialog(window, &info);
    } else if (method == "reveal") {
      PIDLIST_ABSOLUTE pidl = nullptr;
      status = SHParseDisplayName(wide.c_str(), nullptr, &pidl, 0, nullptr);
      if (SUCCEEDED(status)) {
        status = SHOpenFolderAndSelectItems(pidl, 0, nullptr, 0);
        CoTaskMemFree(pidl);
      }
    } else {
      SHELLEXECUTEINFOW info{};
      info.cbSize = sizeof(info);
      info.fMask = SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC;
      info.hwnd = window;
      info.lpVerb = L"open";
      info.lpFile = wide.c_str();
      info.nShow = SW_SHOWNORMAL;
      if (!ShellExecuteExW(&info)) status = HRESULT_FROM_WIN32(GetLastError());
    }
    if (FAILED(status) && status != HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      result->Error("open_failed", "Windows could not open this file.",
          flutter::EncodableValue(static_cast<int64_t>(status)));
    } else {
      result->Success();
    }
  });
}
