/*
 * Nova Runtime Desktop Launcher (nova-runner)
 * Part of Nova Programming Language v0.31.00
 * Copyright (c) 2026 Fyew999 / Nova Systems Team. PolyForm Noncommercial 1.0.0.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#define isatty _isatty
#define fileno _fileno
#else
#include <unistd.h>
#include <sys/wait.h>
#endif

#define NOVA_RUNNER_VERSION "0.31.00"

static void print_usage(const char *prog) {
    printf("Nova Desktop Runtime Launcher v%s\n", NOVA_RUNNER_VERSION);
    printf("Usage: %s [options] <application.nova> [args...]\n\n", prog);
    printf("Options:\n");
    printf("  --hold       Hold terminal console open after application exits\n");
    printf("  --version    Display runtime launcher version\n");
    printf("  --help       Display this help documentation\n\n");
    printf("Description:\n");
    printf("  Provides double-click and desktop execution for Nova native bundles (.nova),\n");
    printf("  analogous to Java's java/javaw runtime environment.\n");
}

static int run_target_with_hold(const char *target, int argc, char **argv, int start_idx) {
    /* Construct execution command */
    char cmd[4096];
    int offset = snprintf(cmd, sizeof(cmd), "\"%s\"", target);
    for (int i = start_idx; i < argc; i++) {
        offset += snprintf(cmd + offset, sizeof(cmd) - offset, " \"%s\"", argv[i]);
        if (offset >= (int)sizeof(cmd) - 1) break;
    }

    /* Execute target binary */
    int status = system(cmd);
    int exit_code = 0;
#ifndef _WIN32
    if (WIFEXITED(status)) {
        exit_code = WEXITSTATUS(status);
    } else {
        exit_code = status;
    }
#else
    exit_code = status;
#endif

    /* Console Hold mechanism */
    printf("\n----------------------------------------------------------\n");
    printf("[Nova Runtime] Process exited with code: %d\n", exit_code);
    printf("Press [Enter] to close this window...");
    fflush(stdout);

    int c;
    while ((c = getchar()) != '\n' && c != EOF) {}
    return exit_code;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    int hold_mode = 0;
    int target_idx = 1;

    if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_usage(argv[0]);
        return 0;
    }

    if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0) {
        printf("nova-runner %s (desktop-runtime x86_64)\n", NOVA_RUNNER_VERSION);
        return 0;
    }

    if (strcmp(argv[1], "--hold") == 0) {
        hold_mode = 1;
        target_idx = 2;
        if (argc < 3) {
            fprintf(stderr, "Error: --hold requires target .nova bundle.\n");
            return 1;
        }
    }

    const char *target = argv[target_idx];

#ifndef _WIN32
    /* Check if running without a TTY (GUI double-click from desktop file manager) */
    if (!hold_mode && !isatty(fileno(stdin))) {
        /* Spawn in an external terminal with --hold */
        const char *terminals[] = {
            "x-terminal-emulator",
            "gnome-terminal",
            "konsole",
            "xfce4-terminal",
            "alacritty",
            "kitty",
            "xterm",
            NULL
        };

        char full_cmd[4096];
        char self_path[1024];
        ssize_t len = readlink("/proc/self/exe", self_path, sizeof(self_path) - 1);
        if (len != -1) {
            self_path[len] = '\0';
        } else {
            strncpy(self_path, argv[0], sizeof(self_path) - 1);
        }

        /* Build arguments to pass */
        char arg_str[2048] = "";
        for (int i = target_idx; i < argc; i++) {
            strncat(arg_str, " \"", sizeof(arg_str) - strlen(arg_str) - 1);
            strncat(arg_str, argv[i], sizeof(arg_str) - strlen(arg_str) - 1);
            strncat(arg_str, "\"", sizeof(arg_str) - strlen(arg_str) - 1);
        }

        /* Try each terminal */
        for (int i = 0; terminals[i] != NULL; i++) {
            if (strcmp(terminals[i], "gnome-terminal") == 0) {
                snprintf(full_cmd, sizeof(full_cmd), "%s -- \"%s\" --hold%s",
                         terminals[i], self_path, arg_str);
            } else {
                snprintf(full_cmd, sizeof(full_cmd), "%s -e \"%s\" --hold%s",
                         terminals[i], self_path, arg_str);
            }

            int ret = system(full_cmd);
            if (ret == 0) {
                return 0;
            }
        }
    }
#endif

    if (hold_mode) {
        return run_target_with_hold(target, argc, argv, target_idx + 1);
    }

    /* Standard direct in-terminal execution */
    char cmd[4096];
    int offset = snprintf(cmd, sizeof(cmd), "\"%s\"", target);
    for (int i = target_idx + 1; i < argc; i++) {
        offset += snprintf(cmd + offset, sizeof(cmd) - offset, " \"%s\"", argv[i]);
        if (offset >= (int)sizeof(cmd) - 1) break;
    }

    return system(cmd);
}
