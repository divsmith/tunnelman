#ifndef PTY_SPAWN_H
#define PTY_SPAWN_H

#include <sys/types.h>

/// Forks a child process that:
///   1. Closes the master PTY fd
///   2. Creates a new session (setsid)
///   3. Sets the slave PTY as the controlling terminal
///   4. Dups slave to stdin/stdout/stderr
///   5. execve()s the shell with the provided env
/// Returns the child PID to the parent, or -1 on error.
pid_t pty_spawn_shell(int master_fd, int slave_fd, const char *shell, char * const *env);

#endif /* PTY_SPAWN_H */
