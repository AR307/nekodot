#ifndef RUNNER_FILE_ACTIONS_H_
#define RUNNER_FILE_ACTIONS_H_

#include <windows.h>
#include <flutter/binary_messenger.h>

void RegisterFileActions(flutter::BinaryMessenger* messenger, HWND window);

#endif
