// CShims.h — the only place where raw Darwin/libproc/mach headers are exposed to Swift.
// Everything above this layer works with typed Swift values (see Sources/Interop).
#ifndef CSHIMS_H
#define CSHIMS_H

#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <errno.h>

/// Returns the pid "responsible" for `pid` (e.g. Google Chrome for a Chrome Helper),
/// or -1 on failure. Exported by libquarantine (part of libSystem) but not declared in
/// any public header. Used only for grouping; never for security decisions.
extern pid_t responsibility_get_pid_responsible_for_pid(pid_t pid);

#endif

// ---- Private IOHID event system (Apple Silicon temperature sensors). Not in any SDK header;
// exported by IOKit.framework. Can change between macOS releases: every caller must degrade.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// ---- AppleSMC user-client wire format (80 bytes). Same layout since the Intel days; on Apple
// Silicon values are mostly "flt " (little-endian float) and "ui8 "/"ui16"/"ui32" (big-endian).
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVersion vers; SMCPLimitData pLimitData; SMCKeyInfo keyInfo;
    uint8_t result, status, data8; uint32_t data32; uint8_t bytes[32];
} SMCKeyData;
