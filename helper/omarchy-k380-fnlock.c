// The K380 speaks HID++ 2.0 on its Bluetooth HID interface. Feature indices
// differ between firmware revisions, so every call resolves them through the
// root feature instead of replaying a hardcoded byte sequence.
//
// Output is always one JSON object on stdout; the exit code is 0 when the
// keyboard answered and 1 otherwise, so the bar widget can read both.

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/file.h>
#include <time.h>
#include <unistd.h>

#define LOGITECH 0x046D
#define K380_PRODUCT 0xB342
#define BUS_BLUETOOTH 0x0005

#define REPORT_SHORT 0x10
#define REPORT_LONG 0x11

#define SHORT_LEN 7
#define LONG_LEN 20

#define DEVICE_INDEX 0xFF // Direct Bluetooth connection, no receiver.
#define SOFTWARE_ID 0x0C

#define TIMEOUT_MS 1000

#define FEATURE_BATTERY_STATUS 0x1000
#define FEATURE_BATTERY_UNIFIED 0x1004

#define FEATURE_FN_INVERSION 0x40A0
#define FEATURE_FN_INVERSION_NEW 0x40A2
#define FEATURE_FN_INVERSION_K375S 0x40A3

#define MAX_KEYBOARDS 16
#define MAX_FEATURES 8

#define MODE_MEDIA "media"
#define MODE_FUNCTION "function"

enum {
    E_OK = 0,
    E_TIMEOUT = -1,
    E_HIDPP = -2,
    E_IO = -3,
};

typedef struct {
    char path[272];
    char address[32];
    char name[128];
    bool hidpp;
} keyboard_t;

typedef struct {
    int fd;
    int io_errno;
    char error[64];
    int feature_count;

    struct {
        uint16_t id;
        uint8_t index;
    } features[MAX_FEATURES];
} hidpp_t;

typedef struct {
    bool present;
    int percent;
    bool approximate;
    bool critical;
    const char *status;
} battery_t;

static const char *hidpp_error_name(int code) {
    switch (code) {
        case 0x01: return "unknown";
        case 0x02: return "invalid argument";
        case 0x03: return "out of range";
        case 0x04: return "hardware error";
        case 0x05: return "logitech internal";
        case 0x06: return "invalid feature index";
        case 0x07: return "invalid function";
        case 0x08: return "busy";
        case 0x09: return "unsupported";
        default: return NULL;
    }
}

static void print_json_string(const char *s) {
    putchar('"');
    for (; *s; s++) {
        unsigned char c = (unsigned char) *s;

        if (c == '"' || c == '\\') {
            printf("\\%c", c);
        } else if (c < 0x20) {
            printf("\\u%04x", c);
        } else {
            putchar(c);
        }
    }
    putchar('"');
}

static void print_json_nullable(const char *s) {
    if (s && *s) print_json_string(s);
    else fputs("null", stdout);
}


static bool read_file(const char *path, char *buf, size_t size, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    *len = fread(buf, 1, size - 1, f);
    buf[*len] = '\0';
    fclose(f);
    return true;
}

static void uevent_value(const char *uevent, const char *key, char *out, size_t size) {
    size_t key_len = strlen(key);
    out[0] = '\0';
    for (const char *line = uevent; line && *line;) {
        const char *end = strchr(line, '\n');
        size_t len = end ? (size_t) (end - line) : strlen(line);
        if (len > key_len && strncmp(line, key, key_len) == 0 && line[key_len] == '=') {
            size_t n = len - key_len - 1;
            if (n >= size) n = size - 1;
            memcpy(out, line + key_len + 1, n);
            out[n] = '\0';
            return;
        }
        line = end ? end + 1 : NULL;
    }
}

// Usage page 0xFF43 is Logitech's HID++ vendor collection.
static bool has_hidpp_collection(const char *sys_dir) {
    char path[512], buf[4096];
    size_t len;
    snprintf(path, sizeof(path), "%s/device/report_descriptor", sys_dir);
    if (!read_file(path, buf, sizeof(buf), &len)) return true;
    return memmem(buf, len, "\x06\x43\xff", 3) != NULL;
}

static int find_keyboards(const char *address, keyboard_t *out, int max) {
    struct dirent **entries;
    int n = scandir("/sys/class/hidraw", &entries, NULL, alphasort);
    if (n < 0) return 0;

    int found = 0;
    for (int i = 0; i < n; i++) {
        const char *node = entries[i]->d_name;
        if (strncmp(node, "hidraw", 6) != 0 || found >= max) continue;

        char sys_dir[300], path[512], uevent[2048], value[160];
        size_t len;
        snprintf(sys_dir, sizeof(sys_dir), "/sys/class/hidraw/%s", node);
        snprintf(path, sizeof(path), "%s/device/uevent", sys_dir);
        if (!read_file(path, uevent, sizeof(uevent), &len)) continue;

        unsigned bus, vendor, product;
        uevent_value(uevent, "HID_ID", value, sizeof(value));
        if (sscanf(value, "%x:%x:%x", &bus, &vendor, &product) != 3) continue;
        if (bus != BUS_BLUETOOTH || vendor != LOGITECH || product != K380_PRODUCT) continue;

        keyboard_t *kb = &out[found];
        uevent_value(uevent, "HID_UNIQ", kb->address, sizeof(kb->address));
        if (address && *address && kb->address[0] && strcasecmp(address, kb->address) != 0) continue;
        for (char *c = kb->address; *c; c++)
            if (*c >= 'a' && *c <= 'f') *c -= 'a' - 'A';
        uevent_value(uevent, "HID_NAME", kb->name, sizeof(kb->name));
        snprintf(kb->path, sizeof(kb->path), "/dev/%s", node);
        kb->hidpp = has_hidpp_collection(sys_dir);
        found++;
    }

    for (int i = 0; i < n; i++) free(entries[i]);
    free(entries);
    return found;
}


static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static void drain(hidpp_t *dev) {
    uint8_t buf[64];
    struct pollfd pfd = {.fd = dev->fd, .events = POLLIN};
    while (poll(&pfd, 1, 0) > 0 && read(dev->fd, buf, sizeof(buf)) > 0) {
    }
}

// Sends one request and waits for the matching answer. `reply` receives the
// 16 payload bytes that follow the report header.
static int hidpp_request(hidpp_t *dev, uint8_t index, uint8_t function,
                         const uint8_t *params, size_t nparams, uint8_t reply[16]) {
    uint8_t report[LONG_LEN] = {0};
    uint8_t tag = (uint8_t) (((function & 0x0F) << 4) | SOFTWARE_ID);
    size_t len = nparams <= SHORT_LEN - 4 ? SHORT_LEN : LONG_LEN;

    report[0] = len == SHORT_LEN ? REPORT_SHORT : REPORT_LONG;
    report[1] = DEVICE_INDEX;
    report[2] = index;
    report[3] = tag;
    if (nparams) memcpy(report + 4, params, nparams);

    drain(dev);
    if (write(dev->fd, report, len) != (ssize_t) len) {
        dev->io_errno = errno;
        return E_IO;
    }

    long deadline = now_ms() + TIMEOUT_MS;
    for (;;) {
        long remaining = deadline - now_ms();
        if (remaining <= 0) return E_TIMEOUT;

        struct pollfd pfd = {.fd = dev->fd, .events = POLLIN};
        int ready = poll(&pfd, 1, (int) remaining);
        if (ready < 0 && errno != EINTR) {
            dev->io_errno = errno;
            return E_IO;
        }
        if (ready <= 0) continue;

        uint8_t data[64] = {0};
        ssize_t got = read(dev->fd, data, sizeof(data));
        if (got < 0) {
            if (errno == EAGAIN || errno == EINTR) continue;
            dev->io_errno = errno;
            return E_IO;
        }
        if (got < 5 || (data[0] != REPORT_SHORT && data[0] != REPORT_LONG) || data[1] != DEVICE_INDEX) continue;

        if (data[2] == 0xFF && data[3] == index && data[4] == tag) {
            int code = got > 5 ? data[5] : 0;
            const char *name = hidpp_error_name(code);
            if (name) snprintf(dev->error, sizeof(dev->error), "%s", name);
            else snprintf(dev->error, sizeof(dev->error), "error 0x%02X", code);
            return E_HIDPP;
        }
        if (data[2] == 0x8F && data[3] == index) {
            snprintf(dev->error, sizeof(dev->error), "device speaks HID++ 1.0 only");
            return E_HIDPP;
        }
        if (data[2] == index && data[3] == tag) {
            memcpy(reply, data + 4, 16);
            return E_OK;
        }
    }
}

// Resolves a feature id to its index through the root feature; 0 means the
// keyboard does not have it.
static int feature_index(hidpp_t *dev, uint16_t id, uint8_t *index) {
    for (int i = 0; i < dev->feature_count; i++) {
        if (dev->features[i].id == id) {
            *index = dev->features[i].index;
            return E_OK;
        }
    }

    uint8_t params[2] = {id >> 8, id & 0xFF}, reply[16];
    int rc = hidpp_request(dev, 0x00, 0, params, sizeof(params), reply);
    if (rc != E_OK) return rc;

    *index = reply[0];
    if (dev->feature_count < MAX_FEATURES) {
        dev->features[dev->feature_count].id = id;
        dev->features[dev->feature_count].index = reply[0];
        dev->feature_count++;
    }
    return E_OK;
}


static int fn_feature(hidpp_t *dev, uint16_t *id, uint8_t *index) {
    static const uint16_t candidates[] = {
        FEATURE_FN_INVERSION, FEATURE_FN_INVERSION_NEW, FEATURE_FN_INVERSION_K375S,
    };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        int rc = feature_index(dev, candidates[i], index);
        if (rc != E_OK) return rc;
        if (*index) {
            *id = candidates[i];
            return E_OK;
        }
    }
    *id = 0;
    return E_OK;
}

static int read_mode(hidpp_t *dev, const char **mode, uint16_t *feature_id) {
    uint8_t index, reply[16];
    int rc = fn_feature(dev, feature_id, &index);
    if (rc != E_OK || !*feature_id) return rc;

    rc = hidpp_request(dev, index, 0, NULL, 0, reply);
    if (rc != E_OK) return rc;
    // 0x40A3 prefixes the state with the host byte.
    uint8_t state = *feature_id == FEATURE_FN_INVERSION_K375S ? reply[1] : reply[0];
    *mode = state & 0x01 ? MODE_MEDIA : MODE_FUNCTION;
    return E_OK;
}

static int write_mode(hidpp_t *dev, const char *mode) {
    uint16_t id;
    uint8_t index, reply[16];
    int rc = fn_feature(dev, &id, &index);
    if (rc != E_OK) return rc;
    if (!id) {
        snprintf(dev->error, sizeof(dev->error), "keyboard has no Fn inversion feature");
        return E_HIDPP;
    }

    uint8_t state = strcmp(mode, MODE_MEDIA) == 0 ? 0x01 : 0x00;
    if (id == FEATURE_FN_INVERSION_K375S) {
        uint8_t params[2] = {0xFF, state};
        return hidpp_request(dev, index, 1, params, sizeof(params), reply);
    }
    return hidpp_request(dev, index, 1, &state, 1, reply);
}

static void read_battery(hidpp_t *dev, battery_t *battery) {
    uint8_t index, caps[16], status[16];
    memset(battery, 0, sizeof(*battery));

    if (feature_index(dev, FEATURE_BATTERY_UNIFIED, &index) == E_OK && index) {
        if (hidpp_request(dev, index, 0, NULL, 0, caps) != E_OK) return;
        if (hidpp_request(dev, index, 1, NULL, 0, status) != E_OK) return;
        uint8_t levels = status[1];
        if (caps[1] & 0x02) battery->percent = status[0];
        else {
            battery->approximate = true;
            if (levels & 0x08) battery->percent = 100;
            else if (levels & 0x04) battery->percent = 50;
            else if (levels & 0x02) battery->percent = 20;
            else battery->percent = 5;
        }
        battery->status = status[2] == 1 || status[2] == 2
                              ? "charging"
                              : status[2] == 3
                                    ? "full"
                                    : "discharging";
        battery->critical = levels & 0x01;
        battery->present = true;
        return;
    }

    if (feature_index(dev, FEATURE_BATTERY_STATUS, &index) == E_OK && index) {
        if (hidpp_request(dev, index, 0, NULL, 0, status) != E_OK) return;
        static const char *names[] = {"discharging", "charging", "charging", "full", "charging"};
        battery->percent = status[0];
        battery->status = status[2] < 5 ? names[status[2]] : "unknown";
        battery->critical = status[0] > 0 && status[0] <= 5;
        battery->present = true;
    }
}


static const char *io_error(int err) {
    return err == ENODEV || err == EIO ? "disconnected" : strerror(err);
}

static int run(const keyboard_t *kb, const char *target_mode, bool toggle) {
    const char *mode = NULL, *error = NULL;
    uint16_t feature_id = 0;
    battery_t battery = {0};
    bool accessible = false, ok = false;

    hidpp_t dev = {.fd = open(kb->path, O_RDWR | O_NONBLOCK | O_CLOEXEC)};
    if (dev.fd < 0) {
        error = errno == EACCES || errno == EPERM ? "permission" : strerror(errno);
        goto print;
    }
    accessible = true;

    int rc = read_mode(&dev, &mode, &feature_id);
    if (rc == E_OK && !feature_id) {
        error = "unsupported";
        goto done;
    }
    if (rc == E_OK) {
        if (toggle) target_mode = strcmp(mode, MODE_MEDIA) == 0 ? MODE_FUNCTION : MODE_MEDIA;
        if (target_mode && strcmp(target_mode, mode) != 0) {
            rc = write_mode(&dev, target_mode);
            if (rc == E_OK) rc = read_mode(&dev, &mode, &feature_id);
        }
    }
    if (rc == E_OK) {
        read_battery(&dev, &battery);
        ok = true;
    } else {
        mode = NULL;
        error = rc == E_TIMEOUT ? "timeout" : rc == E_HIDPP ? dev.error : io_error(dev.io_errno);
    }

done:
    close(dev.fd);
print:
    fputs("{\"found\": true, \"hidraw\": ", stdout);
    print_json_string(kb->path);
    fputs(", \"address\": ", stdout);
    print_json_string(kb->address);
    fputs(", \"name\": ", stdout);
    print_json_string(kb->name);
    printf(", \"accessible\": %s, \"mode\": ", accessible ? "true" : "false");
    print_json_nullable(mode);
    fputs(", \"fnFeature\": ", stdout);
    if (feature_id) printf("\"0x%04X\"", feature_id);
    else fputs("null", stdout);
    fputs(", \"battery\": ", stdout);
    if (battery.present)
        printf("{\"percent\": %d, \"approximate\": %s, \"status\": \"%s\", \"critical\": %s}",
               battery.percent, battery.approximate ? "true" : "false", battery.status,
               battery.critical ? "true" : "false");
    else
        fputs("null", stdout);
    fputs(", \"error\": ", stdout);
    print_json_nullable(error);
    puts("}");
    return ok ? 0 : 1;
}

static int usage(const char *message) {
    fputs("usage: omarchy-k380-fnlock {status,set,toggle} [media|function] [--address MAC]\n", stderr);
    if (message) fprintf(stderr, "omarchy-k380-fnlock: error: %s\n", message);
    return 2;
}

int main(int argc, char **argv) {
    const char *command = NULL, *mode = NULL, *address = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(NULL);
            return 0;
        } else if (strcmp(argv[i], "--address") == 0) {
            if (++i >= argc) return usage("--address needs a value");
            address = argv[i];
        } else if (strncmp(argv[i], "--address=", 10) == 0) {
            address = argv[i] + 10;
        } else if (!command) {
            command = argv[i];
        } else if (!mode) {
            mode = argv[i];
        } else {
            return usage("too many arguments");
        }
    }

    if (!command) return usage("a command is required");
    bool is_set = strcmp(command, "set") == 0;
    bool is_toggle = strcmp(command, "toggle") == 0;
    if (!is_set && !is_toggle && strcmp(command, "status") != 0) return usage("unknown command");
    if (mode && strcmp(mode, MODE_MEDIA) != 0 && strcmp(mode, MODE_FUNCTION) != 0)
        return usage("mode must be media or function");
    if (is_set && !mode) return usage("set needs a mode: media or function");

    // One bar widget runs per monitor and every hidraw reader sees every
    // reply, so concurrent helpers would steal each other's answers.
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    char lock_path[512];
    snprintf(lock_path, sizeof(lock_path), "%s/omarchy-k380-fnlock.lock", runtime && *runtime ? runtime : "/tmp");
    int lock = open(lock_path, O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
    if (lock >= 0) flock(lock, LOCK_EX);

    keyboard_t keyboards[MAX_KEYBOARDS];
    int count = find_keyboards(address, keyboards, MAX_KEYBOARDS);
    if (count == 0) {
        puts("{\"found\": false, \"error\": \"not_found\"}");
        return 1;
    }

    const keyboard_t *kb = &keyboards[0];
    for (int i = 0; i < count; i++) {
        if (keyboards[i].hidpp) {
            kb = &keyboards[i];
            break;
        }
    }

    return run(kb, is_set ? mode : NULL, is_toggle);
}
