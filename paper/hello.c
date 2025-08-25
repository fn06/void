// Based off of Docker's hello-world
// This is standalone program
#include <sys/syscall.h>
#include <unistd.h>
#include <string.h>

int main(int argc, char* argv[]) {
  if (argc <= 1) {
    return 42;
  }
  syscall(SYS_write, STDOUT_FILENO, argv[1], strlen(argv[1]));
  syscall(SYS_write, STDOUT_FILENO, "\n", 1);
  return 0;
}
