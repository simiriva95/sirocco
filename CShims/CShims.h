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
