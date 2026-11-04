#include "file_actions.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <string>

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
