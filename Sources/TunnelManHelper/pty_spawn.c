#include "include/pty_spawn.h"
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>

pid_t pty_spawn_shell(int master_fd, int slave_fd, const char *shell, char * const *env) {
    pid_t pid = fork();
    if (pid < 0) return -1;

    if (pid == 0) {
        /* Child process */
        close(master_fd);

        /* New session so the slave becomes the controlling terminal */
        if (setsid() < 0) _exit(1);

        /* Set slave as controlling terminal */
        if (ioctl(slave_fd, TIOCSCTTY, 0) < 0) _exit(1);

        /* Wire slave to stdin/stdout/stderr */
        if (dup2(slave_fd, STDIN_FILENO)  < 0) _exit(1);
        if (dup2(slave_fd, STDOUT_FILENO) < 0) _exit(1);
        if (dup2(slave_fd, STDERR_FILENO) < 0) _exit(1);
        if (slave_fd > STDERR_FILENO) close(slave_fd);

        /* Change to home directory so the shell starts at ~ */
        const char *home = getenv("HOME");
        if (home) chdir(home);

        char *argv[] = { (char *)shell, NULL };
        execve(shell, argv, env);
        _exit(1);
    }

    /* Parent */
    return pid;
}
