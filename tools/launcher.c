#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef PROJECT_DIR
#define PROJECT_DIR "."
#endif

static const char *find_godot_bin(void) {
    const char *env_bin = getenv("GODOT_BIN");
    if (env_bin && access(env_bin, X_OK) == 0) {
        return env_bin;
    }
    const char *candidates[] = {
        "/opt/homebrew/bin/godot",
        "/usr/local/bin/godot",
        "/Applications/Godot.app/Contents/MacOS/Godot",
        NULL
    };
    for (int i = 0; candidates[i] != NULL; i++) {
        if (access(candidates[i], X_OK) == 0) {
            return candidates[i];
        }
    }
    return "godot";
}

int main(int argc, char **argv) {
    const char *godot = find_godot_bin();
    int has_sep = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) {
            has_sep = 1;
            break;
        }
    }

    char **exec_argv = calloc((size_t)(argc + 6), sizeof(char *));
    if (!exec_argv) {
        perror("calloc");
        return 1;
    }

    int k = 0;
    exec_argv[k++] = (char *)godot;
    exec_argv[k++] = "--path";
    exec_argv[k++] = PROJECT_DIR;

    if (argc > 1 && !has_sep) {
        exec_argv[k++] = "--";
    }
    for (int i = 1; i < argc; i++) {
        exec_argv[k++] = argv[i];
    }
    exec_argv[k] = NULL;

    execvp(godot, exec_argv);
    perror("Failed to launch godot");
    free(exec_argv);
    return 1;
}
