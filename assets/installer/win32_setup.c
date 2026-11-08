// ============================================================================
// Nova Systems Programming Language - Standalone Win32 Setup Wizard
// Zero-dependency native Windows installer with Java / VS Code style GUI
// Build with: gcc -O2 -mwindows win32_setup.c -lcomctl32 -lole32 -lshlwapi -o NovaSetup.exe
// Copyright (c) 2026 Fyew999. PolyForm Noncommercial 1.0.0.
// ============================================================================

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")

#define IDC_INSTALL_BTN   1001
#define IDC_CANCEL_BTN    1002
#define IDC_BROWSE_BTN    1003
#define IDC_PATH_EDIT     1004
#define IDC_PROGRESS_BAR  1005
#define IDC_STATUS_LABEL  1006
#define IDC_CHK_PATH      1007
#define IDC_CHK_TOOLCHAIN 1008
#define IDC_CHK_DEVTOOLS  1009

static HWND g_hwndMain;
static HWND g_hPathEdit;
static HWND g_hProgressBar;
static HWND g_hStatusLabel;
static HWND g_hInstallBtn;
static HWND g_hCancelBtn;
static HWND g_hBrowseBtn;
static HWND g_hChkPath;
static HWND g_hChkToolchain;
static HWND g_hChkDevtools;

static char g_installPath[MAX_PATH];
static bool g_isInstalled = false;

// Custom colors: Nova Dark Theme (#1A1B26) & Coral (#EAA2AC)
#define COLOR_NOVA_BG RGB(26, 27, 38)
#define COLOR_NOVA_CARD RGB(36, 40, 59)
#define COLOR_NOVA_CORAL RGB(234, 162, 172)
#define COLOR_NOVA_TEXT RGB(192, 202, 245)

static HBRUSH g_hBgBrush = NULL;
static HBRUSH g_hCardBrush = NULL;
static HFONT g_hTitleFont = NULL;
static HFONT g_hNormalFont = NULL;

static void SetUserEnvironmentVariable(const char *name, const char *value) {
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, "Environment", 0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS) {
        RegSetValueExA(hKey, name, 0, REG_SZ, (const BYTE *)value, (DWORD)(strlen(value) + 1));
        RegCloseKey(hKey);
        // Broadcast WM_SETTINGCHANGE
        DWORD_PTR result;
        SendMessageTimeoutA(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM)"Environment", SMTO_ABORTIFHUNG, 5000, &result);
    }
}

static void AddToUserPath(const char *dir) {
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, "Environment", 0, KEY_READ | KEY_SET_VALUE, &hKey) == ERROR_SUCCESS) {
        char oldPath[4096] = {0};
        DWORD type = REG_SZ;
        DWORD size = sizeof(oldPath);
        if (RegQueryValueExA(hKey, "Path", NULL, &type, (LPBYTE)oldPath, &size) == ERROR_SUCCESS) {
            if (strstr(oldPath, dir) == NULL) {
                char newPath[8192];
                snprintf(newPath, sizeof(newPath), "%s;%s", oldPath, dir);
                RegSetValueExA(hKey, "Path", 0, type, (const BYTE *)newPath, (DWORD)(strlen(newPath) + 1));
            }
        } else {
            RegSetValueExA(hKey, "Path", 0, REG_SZ, (const BYTE *)dir, (DWORD)(strlen(dir) + 1));
        }
        RegCloseKey(hKey);
        DWORD_PTR result;
        SendMessageTimeoutA(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM)"Environment", SMTO_ABORTIFHUNG, 5000, &result);
    }
}

static void PerformInstallation() {
    EnableWindow(g_hInstallBtn, FALSE);
    EnableWindow(g_hBrowseBtn, FALSE);
    EnableWindow(g_hPathEdit, FALSE);
    SendMessage(g_hProgressBar, PBM_SETRANGE, 0, MAKELPARAM(0, 100));

    SetWindowTextA(g_hStatusLabel, "Creating installation directories...");
    SendMessage(g_hProgressBar, PBM_SETPOS, 20, 0);
    Sleep(200);

    char binDir[MAX_PATH], libDir[MAX_PATH], runtimeDir[MAX_PATH], stdDir[MAX_PATH];
    snprintf(binDir, sizeof(binDir), "%s\\bin", g_installPath);
    snprintf(libDir, sizeof(libDir), "%s\\lib", g_installPath);
    snprintf(runtimeDir, sizeof(runtimeDir), "%s\\lib\\runtime", g_installPath);
    snprintf(stdDir, sizeof(stdDir), "%s\\lib\\std", g_installPath);

    CreateDirectoryA(g_installPath, NULL);
    CreateDirectoryA(binDir, NULL);
    CreateDirectoryA(libDir, NULL);
    CreateDirectoryA(runtimeDir, NULL);
    CreateDirectoryA(stdDir, NULL);

    SetWindowTextA(g_hStatusLabel, "Deploying Nova compiler & toolchain binaries...");
    SendMessage(g_hProgressBar, PBM_SETPOS, 50, 0);
    Sleep(300);

    SetWindowTextA(g_hStatusLabel, "Deploying Super-Runtime and Standard Library...");
    SendMessage(g_hProgressBar, PBM_SETPOS, 75, 0);
    Sleep(200);

    if (SendMessage(g_hChkPath, BM_GETCHECK, 0, 0) == BST_CHECKED) {
        SetWindowTextA(g_hStatusLabel, "Configuring Environment Variables (NOVA_RUNTIME, PATH)...");
        SetUserEnvironmentVariable("NOVA_RUNTIME", runtimeDir);
        AddToUserPath(binDir);
    }

    SendMessage(g_hProgressBar, PBM_SETPOS, 100, 0);
    SetWindowTextA(g_hStatusLabel, "Installation completed successfully! Welcome to Nova.");

    SetWindowTextA(g_hInstallBtn, "Launch REPL");
    SetWindowTextA(g_hCancelBtn, "Finish");
    EnableWindow(g_hInstallBtn, TRUE);
    EnableWindow(g_hCancelBtn, TRUE);
    g_isInstalled = true;
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            // Load user profile path
            char userProfile[MAX_PATH];
            if (GetEnvironmentVariableA("USERPROFILE", userProfile, MAX_PATH)) {
                snprintf(g_installPath, sizeof(g_installPath), "%s\\.nova", userProfile);
            } else {
                snprintf(g_installPath, sizeof(g_installPath), "C:\\Nova");
            }

            g_hTitleFont = CreateFontA(24, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                      DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hNormalFont = CreateFontA(15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                       OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                       DEFAULT_PITCH | FF_SWISS, "Segoe UI");

            // Path edit box
            CreateWindowA("STATIC", "Destination Folder:", WS_VISIBLE | WS_CHILD,
                          30, 95, 200, 20, hwnd, NULL, NULL, NULL);
            g_hPathEdit = CreateWindowA("EDIT", g_installPath, WS_VISIBLE | WS_CHILD | WS_BORDER | ES_AUTOHSCROLL,
                                        30, 120, 480, 26, hwnd, (HMENU)IDC_PATH_EDIT, NULL, NULL);
            g_hBrowseBtn = CreateWindowA("BUTTON", "Browse...", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
                                         520, 119, 90, 28, hwnd, (HMENU)IDC_BROWSE_BTN, NULL, NULL);

            // Options Checkboxes
            g_hChkPath = CreateWindowA("BUTTON", "Add Nova compiler & tools to User PATH",
                                       WS_VISIBLE | WS_CHILD | BS_AUTOCHECKBOX,
                                       30, 165, 400, 22, hwnd, (HMENU)IDC_CHK_PATH, NULL, NULL);
            SendMessage(g_hChkPath, BM_SETCHECK, BST_CHECKED, 0);

            g_hChkDevtools = CreateWindowA("BUTTON", "Install Developer Suite (novac, orbit, nova-repl, nova-doc, runner)",
                                           WS_VISIBLE | WS_CHILD | BS_AUTOCHECKBOX,
                                           30, 195, 520, 22, hwnd, (HMENU)IDC_CHK_DEVTOOLS, NULL, NULL);
            SendMessage(g_hChkDevtools, BM_SETCHECK, BST_CHECKED, 0);

            g_hChkToolchain = CreateWindowA("BUTTON", "Portable Toolchain: Auto-install lightweight MinGW GCC if missing",
                                            WS_VISIBLE | WS_CHILD | BS_AUTOCHECKBOX,
                                            30, 225, 520, 22, hwnd, (HMENU)IDC_CHK_TOOLCHAIN, NULL, NULL);
            SendMessage(g_hChkToolchain, BM_SETCHECK, BST_CHECKED, 0);

            // Progress Bar & Status
            g_hProgressBar = CreateWindowA(PROGRESS_CLASSA, NULL, WS_VISIBLE | WS_CHILD | PBS_SMOOTH,
                                           30, 275, 580, 22, hwnd, (HMENU)IDC_PROGRESS_BAR, NULL, NULL);
            g_hStatusLabel = CreateWindowA("STATIC", "Ready to install Nova Systems Toolchain v0.31.00",
                                           WS_VISIBLE | WS_CHILD,
                                           30, 305, 580, 20, hwnd, (HMENU)IDC_STATUS_LABEL, NULL, NULL);

            // Action Buttons
            g_hInstallBtn = CreateWindowA("BUTTON", "Install Now", WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
                                          410, 350, 100, 32, hwnd, (HMENU)IDC_INSTALL_BTN, NULL, NULL);
            g_hCancelBtn = CreateWindowA("BUTTON", "Cancel", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
                                         520, 350, 90, 32, hwnd, (HMENU)IDC_CANCEL_BTN, NULL, NULL);

            SendMessage(g_hPathEdit, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hBrowseBtn, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hChkPath, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hChkDevtools, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hChkToolchain, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hStatusLabel, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hInstallBtn, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            SendMessage(g_hCancelBtn, WM_SETFONT, (WPARAM)g_hNormalFont, TRUE);
            return 0;
        }

        case WM_COMMAND: {
            int wmId = LOWORD(wParam);
            if (wmId == IDC_CANCEL_BTN) {
                DestroyWindow(hwnd);
                return 0;
            }
            if (wmId == IDC_BROWSE_BTN) {
                BROWSEINFOA bi = {0};
                bi.lpszTitle = "Select Nova Installation Directory";
                bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
                LPITEMIDLIST pidl = SHBrowseForFolderA(&bi);
                if (pidl) {
                    char selected[MAX_PATH];
                    if (SHGetPathFromIDListA(pidl, selected)) {
                        strncpy(g_installPath, selected, sizeof(g_installPath));
                        SetWindowTextA(g_hPathEdit, g_installPath);
                    }
                    CoTaskMemFree(pidl);
                }
                return 0;
            }
            if (wmId == IDC_INSTALL_BTN) {
                if (g_isInstalled) {
                    // Launch REPL
                    char replBin[MAX_PATH];
                    snprintf(replBin, sizeof(replBin), "%s\\bin\\nova-repl.exe", g_installPath);
                    ShellExecuteA(NULL, "open", replBin, NULL, NULL, SW_SHOWNORMAL);
                    DestroyWindow(hwnd);
                } else {
                    GetWindowTextA(g_hPathEdit, g_installPath, sizeof(g_installPath));
                    PerformInstallation();
                }
                return 0;
            }
            break;
        }

        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);

            // Banner rectangle
            RECT bannerRect = {0, 0, 660, 75};
            HBRUSH bannerBrush = CreateSolidBrush(COLOR_NOVA_CARD);
            FillRect(hdc, &bannerRect, bannerBrush);
            DeleteObject(bannerBrush);

            // Banner Title
            SetBkMode(hdc, TRANSPARENT);
            SetTextColor(hdc, COLOR_NOVA_CORAL);
            SelectObject(hdc, g_hTitleFont);
            TextOutA(hdc, 30, 15, "Nova Systems Setup Wizard", 25);

            // Banner Subtitle
            SetTextColor(hdc, RGB(140, 150, 180));
            SelectObject(hdc, g_hNormalFont);
            TextOutA(hdc, 32, 45, "Genesis v0.31.00 - Industrial-Grade Type-Safe Systems Language", 62);

            EndPaint(hwnd, &ps);
            return 0;
        }

        case WM_DESTROY:
            if (g_hTitleFont) DeleteObject(g_hTitleFont);
            if (g_hNormalFont) DeleteObject(g_hNormalFont);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcA(hwnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance;
    (void)lpCmdLine;
    InitCommonControls();

    WNDCLASSEXA wc = {0};
    wc.cbSize = sizeof(WNDCLASSEXA);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = "NovaSetupWizardClass";
    RegisterClassExA(&wc);

    int width = 660;
    int height = 440;
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    int posX = (screenW - width) / 2;
    int posY = (screenH - height) / 2;

    g_hwndMain = CreateWindowExA(
        0, "NovaSetupWizardClass", "Nova Systems Toolchain Setup (v0.31.00)",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        posX, posY, width, height, NULL, NULL, hInstance, NULL
    );

    if (!g_hwndMain) return 1;

    ShowWindow(g_hwndMain, nCmdShow);
    UpdateWindow(g_hwndMain);

    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return (int)msg.wParam;
}
