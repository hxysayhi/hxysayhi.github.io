---
layout: post
title:  "wait非子进程退出"
description: "1. 为什么waitpid只能针对子进程使用？ 2. 利用 kill 命令探测进程的存活情况 3. 使用pidfd_open 来在任意进程结束时获得通知 4. 配置CONFIG_PROC_EVENTS，使用Report process events to userspace的特性在进程结束时获得通知 5. 有什么方法可以改变进程的父进程？"
date:   2022-03-12 22:35:18 +0800
categories: Technology notes
permalink: /posts/2c936b7c/
tags: [IT, linux, process, waitpid, pidfd_open, configProcEvents]
preview: "内容摘要： 1. 为什么waitpid只能针对子进程使用？ 2. 利用 kill 命令探测进程的存活情况 3. 使用pidfd_open 来在任意进程结束时获得通知 4. 配置CONFIG_PROC_EVENTS，使用Report process events to userspace的特性在进程结束时获得通知 5. 有什么方法可以改变进程的父进程？"
---

### 背景

有这样一个业务场景，需要主进程可以监测它创建的子进程是否还存活，通常来说使用 waitpid 来获取子进程的状态变化情况，就可以实现需求。但是我们希望在主进程异常退出重启后还能够监测之前创建的子进程的存活情况，但是waitpid 又只能针对子进程使用。于是就有了以下问题：

1. 为什么waitpid只能针对子进程使用？
2. 有没有什么方法可以改变子进程的父进程？
3. 有没有什么方式可以监测非子进程的退出，或者是其他状态变化？


### 为什么waitpid只能针对子进程使用？

wait, waitpid, waitid 这三个系统函数都是为了等待进程状态发生变化。

```
#include <sys/types.h>
#include <sys/wait.h>

pid_t wait(int *status);

pid_t waitpid(pid_t pid, int *status, int options);

int waitid(idtype_t idtype, id_t id, siginfo_t *infop, int options);
```

这三个系统调用都是用于等待调用进程的子进程的状态改变，并获取到子进程状态变化的相关信息。状态变化包括：子进程终止、子进程收到信号停止、子进程收到信号被唤醒。当进程退出的时候，会进程资源会被回收，但是包含进程pid、进程退出状态、资源使用信息等的一个“最小信息集”会被保留，会在进程表中占用一个位置。当父进程使用 wait 系列函数时可以获取到已经终止的子进程的最小信息集所含信息，同时这些信息被清理，占用的进程表资源被回收。如果父进程没有wait并回收掉已经终结的子进程的进程表资源，子进程就会成为僵尸进程（zombies）。如果进程资源始终占用着进程表资源，将进程表资源耗尽，使得系统无法再创建新的进程。如果父进程终止了，那么僵尸进程会被系统一号进程领养，并由一号进程自动执行 wait 调用，将僵尸进程清理、将所占用的资源回收。

关于这个几个函数的使用细节可以查看 man 手册，有以下几点值得注意：
1. 如果父进程在调用 wait 函数时，子进程的状态已经发生了变化，那么调用会立即返回，否则，会阻塞。但是这个行为可以通过options参数进行配置， options 是一个位控制参数， options 配置上 `WNOHANG` 时可以是调用不阻塞，而是立即返回。
2. 默认情况下 wait 函数只等待 子进程退出进入终结态的情况，这个行为可以通过options参数进行配置，配置上 `WUNTRACED` 时可以 wait 子进程进入 stop 状态，配置上 `WCONTINUED` 可以 wait 处于 stop 状态中的进程被 SIGCONT 信号唤醒。
3. status 参数不为 NULL 时，可以接受进程状态变化的相关信息，这些信息可以通过 相关宏对 status 处理得到。
4. 当 对非子进程调用 wait 系列函数时，会返回错误 ECHILD。


当 对非子进程调用 wait 系列函数时，会返回错误 ECHILD。那么为什么呢？

根据[这个回答](https://unix.stackexchange.com/questions/214908/why-can-the-waitpid-system-call-only-be-used-with-child-processes)，这是由于 wait 函数的工作机制，在 POSIX 系统中，子进程退出时，系统会对其父进程发送 SIGCHLD 信号（[参考](https://diveintosystems.org/book/C13-OS/ipc_signals.html)），而在子进程还没有退出的情况调用 wait 函数，就会一直阻塞等待这个信号到来。因为系统只会对终结掉的进程的父进程发送该信号，因此 wait 系列函数只能对子进程调用。

不过这只能解释 wait 进程终结的应用场景进行解释，对 wait 子进程的其他状态变化，如进入 stop 状态和 从 stop 状态重新被唤醒，并不能合理解释。不过机理应该大致类似，这个后续有待研究。

ref：
- https://linux.die.net/man/2/waitpid
- https://www.ibm.com/docs/en/zos/2.4.0?topic=functions-waitpid-wait-specific-child-process-end
- https://linuxhint.com/waitpid-syscall-in-c/
- https://unix.stackexchange.com/questions/214908/why-can-the-waitpid-system-call-only-be-used-with-child-processes

### 能否改变子进程的父进程？

既然 wait 系列函数只能用于非子进程，那么如果可以改变 进程的父进程，也就可以对原本不是 子进程的进程使用 wait 系列函数。那有没有什么方法可以改变子进程的父进程？

根据[这个回答](https://unix.stackexchange.com/questions/193902/change-the-parent-process-of-a-process#:~:text=The%20parent%20process%20id%20(ppid,that%20the%20parent%20was%20terminated.)，在系统内核外是不能对 进程的父进程信息进行配置修改的，而系统并没有提供相关的系统调用来完成这样的操作。内核只会在进程的父进程退出后，将子进程的 ppid 改为 1 号进程。

### 能否监测非子进程的退出或状态变化？

有没有什么方式可以监测非子进程的退出，或者是其他状态变化？

找到三种方式：

1.利用 kill 探测进程的存活情况

调用 `kill(pid, 0)`， 如果返回值是 -1， 而且 errno 是 ESRCH ，就表示进程已经结束退出。  
这个方法也可以用在命令行中：
`while kill -0 $PID 2>/dev/null; do sleep 1; done`  

或者也可以使用探测 /proc/$pid 是否存在的方式来探知。
同样在命令行中利用 ps 等命令检索也可以达到目的。

2.使用 `pidfd_open` 来在任意进程结束时获得通知

从 linux kernel 5.3 开始系统调用 pidfd_open 可以对给定的 pid 创建一个文件描述符。 这个文件描述符可以用于执行poll操作，在进程退出时获得notification。

参考[man手册](https://man7.org/linux/man-pages/man2/pidfd_open.2.html),使用方法如下：

```
The program below opens a PID file descriptor for the process whose PID is specified as its command-line argument.  It then uses poll(2) to monitor the file descriptor for process exit, as indicated by an EPOLLIN event.

   Program source

       #define _GNU_SOURCE
       #include <sys/types.h>
       #include <sys/syscall.h>
       #include <unistd.h>
       #include <poll.h>
       #include <stdlib.h>
       #include <stdio.h>

       #ifndef __NR_pidfd_open
       #define __NR_pidfd_open 434   /* System call # on most architectures */
       #endif

       static int
       pidfd_open(pid_t pid, unsigned int flags)
       {
           return syscall(__NR_pidfd_open, pid, flags);
       }

       int
       main(int argc, char *argv[])
       {
           struct pollfd pollfd;
           int pidfd, ready;

           if (argc != 2) {
               fprintf(stderr, "Usage: %s <pid>\n", argv[0]);
               exit(EXIT_SUCCESS);
           }

           pidfd = pidfd_open(atoi(argv[1]), 0);
           if (pidfd == -1) {
               perror("pidfd_open");
               exit(EXIT_FAILURE);
           }

           pollfd.fd = pidfd;
           pollfd.events = POLLIN;

           ready = poll(&pollfd, 1, -1);
           if (ready == -1) {
               perror("poll");
               exit(EXIT_FAILURE);
           }

           printf("Events (%#x): POLLIN is %sset\n", pollfd.revents,
                   (pollfd.revents & POLLIN) ? "" : "not ");

           close(pidfd);
           exit(EXIT_SUCCESS);
       }

```

3.使用 ptrace  attach 到想要 wait 的进程上。但是这个会对被 attach 的进程造成一定的影响，像性能影响什么的。

4.配置CONFIG_PROC_EVENTS，使用Report process events to userspace的特性在进程结束时获得通知。

这种方式在 github 有相关的项目实现，可以[参考](https://github.com/stormc/waitforpid/blob/master/waitforpid.c).

以及[相关描述](https://www.kernelconfig.io/config_proc_events)：

```
Report process events to userspace
modulename: cn_proc.ko
configname: CONFIG_PROC_EVENTS
Linux Kernel Configuration
└─> Device Drivers
    └─> Connector - unified userspace <-> kernelspace linker
        └─> Report process events to userspace

Provide a connector that reports process events to userspace. Send
events such as fork, exec, id change (uid, gid, suid, etc), and exit.
```


ref:
- https://stackoverflow.com/q/1157700/6364089
- https://stackoverflow.com/q/60183544/6364089
- https://github.com/stormc/waitforpid/blob/master/waitforpid.c
- https://www.kernelconfig.io/config_proc_events


---

后记：

后续可以对wait系列函数以及系统信号机制做更多调研，弄明白遗留的问题。可以对几种 wait 非子进程的方式做更多的实践。

