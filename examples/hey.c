// Based off of Docker's hello-world
// This is standalone program
#include <sys/syscall.h>
#include <unistd.h>

const char message[] = "Hello from the Void!\n";

int main() {
  syscall(SYS_write, STDOUT_FILENO, message, sizeof(message) - 1);
  return 0;
}
