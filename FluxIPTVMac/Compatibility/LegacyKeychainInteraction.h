#ifndef FLUX_LEGACY_KEYCHAIN_INTERACTION_H
#define FLUX_LEGACY_KEYCHAIN_INTERACTION_H

#include <stdbool.h>
#include <stdint.h>
#include <TargetConditionals.h>

#if TARGET_OS_OSX
// macOS only. Keep the deprecated Security types out of the Swift interface.
int32_t FluxLegacyKeychainGetInteractionAllowed(bool *allowed);
int32_t FluxLegacyKeychainSetInteractionAllowed(bool allowed);
#elif TARGET_OS_TV
#include <CoreFoundation/CoreFoundation.h>

// tvOS has no public LAContext. Borrow the canonical Security value; callers
// must not release it. This preserves the existing noninteractive policy.
CFStringRef _Nonnull FluxTVKeychainAuthenticationUIFail(void) CF_RETURNS_NOT_RETAINED;
#endif

#endif
