#include "LegacyKeychainInteraction.h"
#include <Security/Security.h>

// Existing credentials use the file-based macOS keychain. Authentication-UI
// options for the data-protection keychain do not replace this process setting
// for legacy ACLs (Apple TN3137). Keep these two compatibility calls isolated;
// do not suppress deprecation warnings elsewhere or migrate the user's items.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

int32_t FluxLegacyKeychainGetInteractionAllowed(bool *allowed) {
    if (allowed == NULL) { return errSecParam; }
    Boolean previous = true;
    OSStatus status = SecKeychainGetUserInteractionAllowed(&previous);
    if (status == errSecSuccess) { *allowed = previous != 0; }
    return status;
}

int32_t FluxLegacyKeychainSetInteractionAllowed(bool allowed) {
    return SecKeychainSetUserInteractionAllowed(allowed);
}

#pragma clang diagnostic pop
