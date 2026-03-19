import Testing
import Foundation

@Suite("Build Verification Tests")
struct BuildVerificationTests {

    /// Reads Package.swift and extracts product names to verify no case-insensitive collisions.
    private func productNames() throws -> [String] {
        // Find Package.swift relative to the test bundle
        let packageSwiftPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KnokCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Package.swift")

        let contents = try String(contentsOf: packageSwiftPath, encoding: .utf8)

        // Extract product names from .library(name: "X") and .executable(name: "X")
        let pattern = #/\.(library|executable)\(name:\s*"([^"]+)"/#
        return contents.matches(of: pattern).map { String($0.output.2) }
    }

    @Test("Product names do not collide case-insensitively")
    func noProductNameCaseCollision() throws {
        let names = try productNames()
        let lowered = names.map { $0.lowercased() }
        let unique = Set(lowered)

        #expect(
            unique.count == lowered.count,
            "Case-insensitive product name collision detected among: \(names)"
        )
    }

    @Test("No product name matches package name case-insensitively")
    func productNameDoesNotMatchPackageName() throws {
        let names = try productNames()
        let packageName = "Knok"

        for name in names {
            #expect(
                name.lowercased() != packageName.lowercased(),
                "Product '\(name)' collides with package name '\(packageName)' case-insensitively"
            )
        }
    }

    @Test("Expected products exist in Package.swift")
    func expectedProductsExist() throws {
        let names = try productNames()

        #expect(names.contains("KnokCore"), "Missing product: KnokCore")
        #expect(names.contains("knok-cli"), "Missing product: knok-cli")
        #expect(names.contains("knok-mcp"), "Missing product: knok-mcp")
    }

    @Test("CLI product is not named 'knok' (case-insensitive collision risk)")
    func cliNotNamedKnok() throws {
        let names = try productNames()

        for name in names {
            if name.lowercased().hasPrefix("knok") && !name.contains("-") && !name.contains("Core") && !name.contains("App") {
                Issue.record("Product '\(name)' risks case-insensitive collision with app binary 'Knok'")
            }
        }
    }
}
