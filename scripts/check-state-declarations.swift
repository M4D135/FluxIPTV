// Syntax and declaration guard, including code inside inactive platform branches.
import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

final class StateVisitor: SyntaxVisitor {
    let path: String
    let locations: SourceLocationConverter
    var errors = 0
    let singleBindingAttributes: Set<String> = ["State", "Binding", "FocusState", "GestureState", "StateObject", "ObservedObject", "EnvironmentObject", "AppStorage", "SceneStorage", "Published"]
    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        self.locations = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let attributes = node.attributes.compactMap { entry -> String? in
            guard case .attribute(let attribute) = entry else { return nil }
            return attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init)
        }
        let relevant = attributes.filter { singleBindingAttributes.contains($0) }
        if !relevant.isEmpty && (node.bindings.count != 1 || node.bindings.first?.pattern.is(IdentifierPatternSyntax.self) != true || node.bindingSpecifier.text != "var") {
            let location = locations.location(for: node.positionAfterSkippingLeadingTrivia)
            print("\(path):\(location.line):\(location.column): error: @\(relevant[0]) requires one named var per declaration")
            errors += 1
        }
        return .visitChildren
    }
}
let paths = Array(CommandLine.arguments.dropFirst())
var syntaxErrors = 0
var declarationErrors = 0
for path in paths {
    let tree = Parser.parse(source: try String(contentsOfFile: path, encoding: .utf8))
    // SwiftParser recovers malformed input into a tree. Walking that tree alone
    // would silently accept syntax errors, even ones that break every Apple SDK.
    let locations = SourceLocationConverter(fileName: path, tree: tree)
    for diagnostic in ParseDiagnosticsGenerator.diagnostics(for: tree) where diagnostic.diagMessage.severity == .error {
        let location = diagnostic.location(converter: locations)
        print("\(path):\(location.line):\(location.column): error: \(diagnostic.message)")
        syntaxErrors += 1
    }
    let visitor = StateVisitor(path: path, tree: tree)
    visitor.walk(tree)
    declarationErrors += visitor.errors
}
print("Checked \(paths.count) Swift files: \(syntaxErrors) syntax errors, \(declarationErrors) invalid attributed declarations")
exit(syntaxErrors == 0 && declarationErrors == 0 ? 0 : 1)
