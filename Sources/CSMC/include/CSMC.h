#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>
#include <string.h>

// Layout of the structs exchanged with the AppleSMC IOKit user client
// (selector kSMCHandleYPCEvent). The total size must be 80 bytes.

typedef struct {
    char major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

enum {
    kSMCHandleYPCEvent = 2
};

enum {
    kSMCCommandReadKey = 5,
    kSMCCommandWriteKey = 6,
    kSMCCommandGetKeyFromIndex = 8,
    kSMCCommandGetKeyInfo = 9
};

// Swift can't index a fixed C array without tuple gymnastics; these keep that out of Swift.
static inline void smc_set_bytes(SMCKeyData *data, const uint8_t *src, uint32_t count) {
    memset(data->bytes, 0, sizeof(data->bytes));
    if (count > sizeof(data->bytes)) { count = sizeof(data->bytes); }
    memcpy(data->bytes, src, count);
}

static inline void smc_get_bytes(const SMCKeyData *data, uint8_t *dst, uint32_t count) {
    if (count > sizeof(data->bytes)) { count = sizeof(data->bytes); }
    memcpy(dst, data->bytes, count);
}

static inline uint32_t smc_struct_size(void) {
    return (uint32_t)sizeof(SMCKeyData);
}

#endif
