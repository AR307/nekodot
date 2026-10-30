Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

Name "nekodot"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\nekodot"
InstallDirRegKey HKCU "Software\app.nekodot.client" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ManifestDPIAware true
VIProductVersion "${NUMERIC_VERSION}"
VIAddVersionKey "ProductName" "nekodot"
VIAddVersionKey "FileDescription" "nekodot Windows Installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "nekodot contributors · MIT License"
!define MUI_ICON "${ROOT}\apps\native\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "${MUI_ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\nekodot_native.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${ROOT}\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

LangString AppRunning ${LANG_ENGLISH} "Please quit nekodot from its tray menu, then retry. Your server tasks and data will not be changed."
LangString AppRunning ${LANG_SIMPCHINESE} "请先从托盘菜单退出 nekodot，再重试。服务器任务和数据不受影响。"
LangString RecycleNotice ${LANG_ENGLISH} "Only this installed program and its shortcuts will be moved to the Recycle Bin. Login settings, server profiles and chat history are kept. Continue?"
LangString RecycleNotice ${LANG_SIMPCHINESE} "仅将此安装目录和快捷方式移到回收站，保留登录设置、服务器 profiles 和聊天历史。是否继续？"

Function .onInit
  ${IfNot} ${AtLeastBuild} 19045
    MessageBox MB_OK|MB_ICONSTOP "nekodot requires Windows 10 22H2 or Windows 11 x64."
    Abort
  ${EndIf}
  ${IfNot} ${IsNativeAMD64}
    MessageBox MB_OK|MB_ICONSTOP "nekodot requires Windows x64."
    Abort
  ${EndIf}
FunctionEnd

Section "nekodot"
  SetShellVarContext current
  retry:
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "nekodot"
  ${If} $0 != 0
    MessageBox MB_RETRYCANCEL|MB_ICONINFORMATION "$(AppRunning)" IDRETRY retry
    Abort
  ${EndIf}
  SetOutPath "$INSTDIR"
  File /r /x *.pdb /x *.lib /x *.exp "${BUNDLE}\*"
  ; App-local official MSVC runtime; no global runtime installation or admin prompt.
  File "${VC_REDIST}\*.dll"
  File "${ROOT}\LICENSE"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateDirectory "$SMPROGRAMS\nekodot"
  CreateShortcut "$SMPROGRAMS\nekodot\nekodot.lnk" "$INSTDIR\nekodot_native.exe"
  WriteRegStr HKCU "Software\app.nekodot.client" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "DisplayName" "nekodot"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "Publisher" "nekodot contributors"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "DisplayIcon" "$INSTDIR\nekodot_native.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "UninstallString" '$\"$INSTDIR\uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "URLInfoAbout" "https://nekodot.com"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client" "NoRepair" 1
SectionEnd

Function un.Recycle
  Pop $0
  ; SHFileOperation uses a double-NUL terminated list of UTF-16 paths.
  StrLen $1 $0
  IntOp $1 $1 + 2
  IntOp $2 $1 * 2
  System::Alloc $2
  Pop $2
  System::Call '*$2(&w$1 r0)'
  System::Call '*(p 0, i 3, p r2, p 0, &i2 0x0040, i 0, p 0, p 0) p.r3'
  System::Call 'shell32::SHFileOperationW(p r3) i.r4'
  System::Free $3
  System::Free $2
  ${If} $4 != 0
    MessageBox MB_OK|MB_ICONSTOP "Could not move the program to the Recycle Bin. Files and settings have been kept."
    Abort
  ${EndIf}
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  IfSilent 0 +2
    Abort
  MessageBox MB_YESNO|MB_ICONQUESTION "$(RecycleNotice)" IDYES +2
    Abort
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "nekodot"
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONINFORMATION "$(AppRunning)"
    Abort
  ${EndIf}
  Push "$INSTDIR"
  Call un.Recycle
  Push "$SMPROGRAMS\nekodot"
  Call un.Recycle
  DeleteRegKey HKCU "Software\app.nekodot.client"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nekodot.client"
SectionEnd
