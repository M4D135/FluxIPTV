import Foundation
import Security

@main
@MainActor
struct KeychainInteractionSmoke {
    enum Failure: Error { case expectedThrow, assertion(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.assertion(message) }
    }

    static func isInteractionAllowed() throws -> Bool {
        var value = false
        try require(FluxLegacyKeychainGetInteractionAllowed(&value) == errSecSuccess,
                    "Cannot read process interaction state")
        return value
    }

    static func setInteraction(_ value: Bool) throws {
        try require(FluxLegacyKeychainSetInteractionAllowed(value) == errSecSuccess,
                    "Cannot set process interaction state")
    }

    static func main() throws {
        let initial = try isInteractionAllowed()
        defer { _ = FluxLegacyKeychainSetInteractionAllowed(initial) }

        try setInteraction(true)
        let result = try IPTVKeychain.withSilentInteractionForTesting {
            try require(!isInteractionAllowed(), "Silent operation allowed interaction")
            try IPTVKeychain.withSilentInteractionForTesting {
                try require(!isInteractionAllowed(), "Nested operation allowed interaction")
            }
            try require(!isInteractionAllowed(), "Nested guard changed outer state")
            return 42
        }
        try require(result == 42, "Guard did not return operation result")
        try require(isInteractionAllowed(), "Success did not restore enabled state")

        do {
            try IPTVKeychain.withSilentInteractionForTesting {
                try require(!isInteractionAllowed(), "Throwing operation allowed interaction")
                throw Failure.expectedThrow
            }
            throw Failure.assertion("Guard swallowed the operation error")
        } catch Failure.expectedThrow { }
        try require(isInteractionAllowed(), "Failure did not restore enabled state")

        try setInteraction(false)
        try IPTVKeychain.withSilentInteractionForTesting {
            try require(!isInteractionAllowed(), "Disabled setting was not preserved")
        }
        try require(!isInteractionAllowed(), "Guard enabled a previously disabled setting")
        print("PASS: silent Keychain guard, nesting, error propagation and exact restoration; no credential items accessed")
    }
}
