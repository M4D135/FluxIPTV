#ifndef FLUX_LEGACY_KEYCHAIN_INTERACTION_H
#define FLUX_LEGACY_KEYCHAIN_INTERACTION_H

#include <stdbool.h>
#include <stdint.h>

// macOS only. Keep the deprecated Security types out of the Swift interface.
int32_t FluxLegacyKeychainGetInteractionAllowed(bool *allowed);
int32_t FluxLegacyKeychainSetInteractionAllowed(bool allowed);

#endif
