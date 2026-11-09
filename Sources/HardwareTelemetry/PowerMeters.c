#include "HardwareTelemetry.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <math.h>
#include <string.h>

typedef struct {
    uint32_t key;
    uint8_t reservedA[24];
    uint32_t count, format;
    uint8_t reservedB[4];
    uint8_t result, reservedC, command, reservedD[5], payload[32];
} SNKeyMessage;
_Static_assert(sizeof(SNKeyMessage) == 80, "Unexpected SMC message alignment");

static uint32_t code(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16)
         | ((uint32_t)(uint8_t)s[2] << 8) | (uint8_t)s[3];
}
bool SNDecodeSMCScalar(const char *format, const uint8_t *bytes, uint32_t count, double *value) {
    if (!format || !bytes || !value) return false;
    uint32_t type = code(format);
    double number;
    if (type == code("flt ") && count == 4) {
        float f; memcpy(&f, bytes, 4); number = f;
    } else if (type == code("fpe2") && count == 2) {
        number = ((uint16_t)bytes[0] << 8 | bytes[1]) / 4.0;
    } else if (type == code("sp78") && count == 2) {
        number = (int16_t)((uint16_t)bytes[0] << 8 | bytes[1]) / 256.0;
    } else return false;
    if (!isfinite(number)) return false;
    *value = number;
    return true;
}
bool SNDecodeBatteryScalar(const char *format, const uint8_t *bytes, uint32_t count, bool current, double *value) {
    if (!format || !bytes || !value) return false;
    double number;
    if (count == 2 && code(format) == code(current ? "si16" : "ui16")) {
        uint16_t raw = (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
        number = (current ? (double)(int16_t)raw : (double)raw) / 1000.0;
    } else if (!SNDecodeSMCScalar(format, bytes, count, &number)) return false;
    if (!isfinite(number) || (current ? fabs(number) > 50 : (number < 1 || number > 30))) return false;
    *value = number;
    return true;
}
static bool payload(io_connect_t connection, const char *key, SNKeyMessage *reply) {
    SNKeyMessage request = {0};
    request.key = code(key); request.command = 9;
    size_t size = sizeof(*reply);
    memset(reply, 0, size);
    if (IOConnectCallStructMethod(connection, 2, &request, sizeof(request), reply, &size) != KERN_SUCCESS
        || size != sizeof(*reply) || reply->result || reply->count > 32) return false;
    uint32_t format = reply->format;
    request.count = reply->count; request.command = 5;
    memset(reply, 0, sizeof(*reply)); size = sizeof(*reply);
    if (IOConnectCallStructMethod(connection, 2, &request, sizeof(request), reply, &size) != KERN_SUCCESS
        || size != sizeof(*reply) || reply->result) return false;
    reply->format = format; reply->count = request.count;
    return true;
}
static bool scalar(io_connect_t connection, const char *key, double *value) {
    SNKeyMessage reply;
    if (!payload(connection, key, &reply)) return false;
    char name[4] = {(char)(reply.format >> 24), (char)(reply.format >> 16), (char)(reply.format >> 8), (char)reply.format};
    return SNDecodeSMCScalar(name, reply.payload, reply.count, value);
}
#if defined(__arm64__)
static bool batteryScalar(io_connect_t connection, bool current, double *value) {
    SNKeyMessage reply;
    if (!payload(connection, current ? "B0AC" : "B0AV", &reply)) return false;
    char name[4] = {(char)(reply.format >> 24), (char)(reply.format >> 16), (char)(reply.format >> 8), (char)reply.format};
    return SNDecodeBatteryScalar(name, reply.payload, reply.count, current, value);
}
#endif
bool SNReadPowerMeters(SNPowerMeters *meters) {
    if (!meters) return false;
    memset(meters, 0, sizeof(*meters));
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return false;
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) return false;
    double value;
    if (scalar(connection, "PSTR", &value) && value > 0 && value <= 1000) {
        meters->systemWatts = value; meters->validMask |= 1;
    }
    if (scalar(connection, "PDTR", &value) && value >= 0 && value <= 1000) {
        meters->inputWatts = value; meters->validMask |= 2;
    }
    bool displayRead = scalar(connection, "PDBR", &value);
    if (!displayRead) displayRead = scalar(connection, "PBwo", &value);
    if (displayRead && value >= 0 && value <= 150) {
        meters->displayWatts = value; meters->validMask |= 4;
    }
    for (int i = 0; i < 4; ++i) {
        char voltsKey[] = "D1JV", ampsKey[] = "D1JI";
        voltsKey[1] += i; ampsKey[1] += i;
        double volts, amps;
        if (scalar(connection, voltsKey, &volts) && scalar(connection, ampsKey, &amps)
            && volts >= 0 && volts <= 60 && amps >= 0 && amps <= 10 && volts * amps <= 150) {
            meters->outputWatts[i] = volts * amps; meters->validMask |= (8u << i);
        }
    }
#if defined(__arm64__)
    double volts, amps;
    if (batteryScalar(connection, false, &volts) && batteryScalar(connection, true, &amps)
        && fabs(volts * amps) <= 1000) {
        meters->batteryNetWatts = volts * amps; meters->validMask |= 128;
    }
#endif
    IOServiceClose(connection);
    return meters->validMask != 0;
}
