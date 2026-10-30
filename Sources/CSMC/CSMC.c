#include "CSMC.h"

// SwiftPM requires a C target to have at least one translation unit.
// Compile-time guard for the ABI the AppleSMC user client expects.
_Static_assert(sizeof(SMCKeyData) == 80, "SMCKeyData must be 80 bytes");
