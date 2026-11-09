#ifndef STATUSNAV_HARDWARE_TELEMETRY_H
#define STATUSNAV_HARDWARE_TELEMETRY_H
#include <stdbool.h>
#include <stdint.h>
typedef struct {
    double systemWatts, inputWatts, displayWatts, batteryNetWatts;
    double outputWatts[4];
    uint32_t validMask;
} SNPowerMeters;
/* Read-only, fixed sensor keys. Missing sensors leave their mask bit unset. */
bool SNReadPowerMeters(SNPowerMeters *meters);
bool SNDecodeBatteryScalar(const char *format, const uint8_t *bytes, uint32_t count, bool current, double *value);
bool SNDecodeSMCScalar(const char *format, const uint8_t *bytes, uint32_t count, double *value);
#endif
