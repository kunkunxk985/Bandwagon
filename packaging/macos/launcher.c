// Bandwagon App 启动器：找到项目目录里的 .venv 并 exec python。
// 用编译二进制而不是脚本，因为 LaunchServices 要求主执行文件是 Mach-O。
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>
#include <mach-o/dyld.h>

static void show_alert(const char *msg);

static int try_launch(const char *root) {
    if (!root || !*root) return 1;
    char python[1024];
    snprintf(python, sizeof(python), "%s/.venv/bin/python", root);
    if (access(python, X_OK) != 0) return 1;
    if (chdir(root) != 0) return 1;
    setenv("PYTHONUNBUFFERED", "1", 1);
    char *argv[] = { python, "-m", "app.desktop", NULL };
    execv(python, argv);
    return 1;
}

static void show_alert(const char *msg) {
    char cmd[4096];
    snprintf(cmd, sizeof(cmd),
             "osascript -e 'display alert \"Bandwagon\" message \"%s\"'", msg);
    system(cmd);
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    const char *home = getenv("HOME");
    if (!home || !*home) {
        show_alert("未找到 HOME 目录，无法启动。");
        return 1;
    }

    char root[2048];
    const char *names[] = { "Bandwagon", "WagongDeck", "bandwagon" };
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
        snprintf(root, sizeof(root), "%s/Desktop/%s", home, names[i]);
        if (try_launch(root) == 0) return 0;
    }

    show_alert("未找到运行环境，请确认项目在 ~/Desktop/Bandwagon，并已执行 ./start.sh 安装依赖。");
    return 1;
}
