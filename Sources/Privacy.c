#include "Privacy.h"
#include <sandbox.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <unistd.h>

int enter_offline_sandbox(void) {
    char *error = NULL;
    int result = sandbox_init("(version 1)(allow default)(deny network*)", 0, &error);
    if (error) sandbox_free_error(error);
    return result;
}

int outbound_network_is_denied(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return errno == EPERM || errno == EACCES;
    struct timeval timeout = {1, 0};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(443);
    inet_pton(AF_INET, "1.1.1.1", &address.sin_addr);
    int result = connect(fd, (struct sockaddr *)&address, sizeof(address));
    int denied = result < 0 && (errno == EPERM || errno == EACCES);
    close(fd);
    return denied;
}

