// 瓦工台 App 启动器：找到项目目录里的 .venv 并 exec python。
// 用编译二进制而不是脚本，因为 LaunchServices 要求主执行文件是 Mach-O。
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>
#include <mach-o/dyld.h>

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

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    char exe[1024] = "";
    uint32_t size = sizeof(exe);
    _NSGetExecutablePath(exe, &size);

    // 启动器位于 <项目>.app/Contents/MacOS/，向上三级取 .app 所在目录
    char tmp[1024];
    strncpy(tmp, exe, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';
    char *dir = dirname(tmp); // Contents/MacOS
    strncpy(tmp, dir, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';
    dir = dirname(tmp); // Contents
    strncpy(tmp, dir, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';
    dir = dirname(tmp); // 瓦工台.app
    strncpy(tmp, dir, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';
    dir = dirname(tmp); // .app 所在目录

    // 1. 如果 .app 位于 dist/ 目录，向上一级探测项目根目录
    char parent[1024];
    snprintf(parent, sizeof(parent), "%s/..", dir);
    if (try_launch(parent) == 0) return 0;

    // 2. 探测 .app 同级目录
    if (try_launch(dir) == 0) return 0;

    // 3. 探测 .app 同级子目录
    char root[1024];
    const char *names[] = { "Banwagon", "瓦工台", "WagongDeck", "banwagon" };
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
        snprintf(root, sizeof(root), "%s/%s", dir, names[i]);
        if (try_launch(root) == 0) return 0;
    }

    // 4. 探测 ~/Desktop / ~/
    const char *home = getenv("HOME");
    if (home && *home) {
        for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
            snprintf(root, sizeof(root), "%s/Desktop/%s", home, names[i]);
            if (try_launch(root) == 0) return 0;
            snprintf(root, sizeof(root), "%s/%s", home, names[i]);
            if (try_launch(root) == 0) return 0;
        }
    }

    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
             "osascript -e 'display alert \"瓦工台\" message \"未找到运行环境，请先在终端执行：\\ncd ~/Desktop/Banwagon && ./start.sh\"'");
    system(cmd);
    return 1;
}
