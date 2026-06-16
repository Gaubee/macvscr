#ifndef VSCBRIDGE_H
#define VSCBRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <CoreGraphics/CoreGraphics.h>  // CGDirectDisplayID

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a live virtual display.
typedef struct VSCDisplay *VSCDisplayRef;

/// Description of the virtual display to create.
typedef struct {
    uint32_t   width;        // physical pixels wide (backing store)
    uint32_t   height;       // physical pixels high (backing store)
    double     refreshRate;  // Hz (60 is a safe default)
    double     scale;        // backing scale = physical/logical (2.0 = Retina @2x)
    double     ppi;          // pixels per inch, drives sizeInMillimeters
    const char *name;        // UTF-8 display name; encoded identity
} VSCDisplayConfig;

/// Create a virtual display. On success returns a non-NULL handle and, if
/// outDisplayID != NULL, writes the new CGDirectDisplayID. Returns NULL on
/// failure (e.g. the private SPI changed shape on a future macOS).
VSCDisplayRef vsc_create(const VSCDisplayConfig *cfg, uint32_t *outDisplayID);

/// Tear down the virtual display (releases the strong reference). NULL-safe.
void vsc_destroy(VSCDisplayRef ref);

/// The CGDirectDisplayID of a live display, or 0 if invalid.
uint32_t vsc_display_id(VSCDisplayRef ref);

#ifdef __cplusplus
}
#endif

#endif /* VSCBRIDGE_H */
