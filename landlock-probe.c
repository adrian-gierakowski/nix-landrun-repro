#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/landlock.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char ** argv)
{
    if (argc == 2 && strcmp(argv[1], "--check-denied") == 0) {
        int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (fd < 0 && errno == EACCES)
            return 0;
        if (fd >= 0)
            close(fd);
        fprintf(stderr, "Invalid test environment: opening / was not denied with EACCES\n");
        return 1;
    }
    if (argc != 1) {
        fprintf(stderr, "Usage: landlock-probe [--check-denied]\n");
        return 1;
    }
    int abi = syscall(SYS_landlock_create_ruleset, NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 1) {
        fprintf(stderr, "Landlock ABI 1 or newer is required: %s\n", abi < 0 ? strerror(errno) : "unavailable");
        return 1;
    }
    printf("Landlock ABI: %d\n", abi);
    return 0;
}
