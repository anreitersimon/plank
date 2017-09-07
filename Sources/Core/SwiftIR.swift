//
//  SwiftIR.swift
//  plank
//
//  Created by anreitersimon on 9/3/17.
//
//

import Foundation

extension String {
    // Objective-C String Literal
    func swiftLiteral() -> String {
        return "\"\(self)\""
    }
}

extension Sequence {
    func swiftLiteral() -> String {
        let inner = self.map { "\($0)" }.joined(separator: ", ")
        return "[\(inner)]"
    }
}

typealias SimpleSwiftProperty = SwiftIR.Property

func swiftEnumTypeName(propertyName: String, className: String) -> String {
    return propertyName.snakeCaseToPropertyName().uppercaseFirst
}

public struct SwiftIR {

    static let ret = "return"

    static func method(_ signature: String, body: () -> [String]) -> SwiftIR.Method {
        return SwiftIR.Method(body: body(), signature: signature)
    }

    static func stmt(_ body: String) -> String {
        return "\(body)"
    }

    static func block(_ params: [Parameter], body: () -> [String]) -> String {
        return [
            "{ " + (params.count == 0 ? "" : "(\(params.joined(separator: ", ")))") + "in",
            -->body,
            "}"
            ].joined(separator: "\n")
    }

    static func scope(body: () -> [String]) -> String {
        return [
            "{",
            -->body,
            "}"
            ].joined(separator: "\n")
    }

    enum SwitchCase {
        case caseStmt(condition: String, body: () -> [String])
        case defaultStmt(body: () -> [String])

        func render() -> String {
            switch self {
            case .caseStmt(let condition, let body):
                return [ "case \(condition):",
                    -->body,
                    -->[SwiftIR.stmt("break")]
                    ].joined(separator: "\n")
            case .defaultStmt(let body):
                return [ "default:",
                         -->body,
                         -->[SwiftIR.stmt("break")]
                    ].joined(separator: "\n")
            }
        }
    }

    static func caseStmt(_ condition: String, body: @escaping () -> [String]) -> SwitchCase {
        return .caseStmt(condition: condition, body: body)
    }

    static func defaultCaseStmt(body: @escaping () -> [String]) -> SwitchCase {
        return .defaultStmt(body: body)
    }

    static func switchStmt(_ switchVariable: String, body: () -> [SwitchCase]) -> String {
        return [
            "switch \(switchVariable) {",
            body().map { $0.render() }.joined(separator: "\n"),
            "}"
            ].joined(separator: "\n")
    }
    static func ifStmt(_ condition: String, body: () -> [String]) -> String {
        return [
            "if \(condition) {",
            -->body,
            "}"
            ].joined(separator: "\n")
    }

    static func elseIfStmt(_ condition: String, _ body:() -> [String]) -> String {
        return [
            " else if \(condition) {",
            -->body,
            "}"
            ].joined(separator: "\n")
    }

    static func elseStmt(_ body: () -> [String]) -> String {
        return [
            " else {",
            -->body,
            "}"
            ].joined(separator: "\n")
    }

    static func ifElseStmt(_ condition: String, body: @escaping () -> [String]) -> (() -> [String]) -> String {
        return { elseBody in [
            SwiftIR.ifStmt(condition, body: body) +
                SwiftIR.elseStmt(elseBody)
            ].joined(separator: "\n") }
    }

    static func forStmt(_ condition: String, body: () -> [String]) -> String {
        return [
            "for \(condition) {",
            -->body,
            "}"
            ].joined(separator: "\n")
    }

    static func enumStmt(_ enumName: String, body: () -> [String]) -> String {
        return [
            "enum \(enumName) {",
            -->[body().joined(separator: "\n")],
            "}"
            ].joined(separator: "\n")
    }

    public struct Method {
        let body: [String]
        let signature: String

        func render() -> [String] {
            return [
                "\(signature) {",
                -->body,
                "}"
            ]
        }
    }

    public struct Property {

        enum Accessor {
            case stored
            case readOnly(getter: () -> [String])
            case computed(getter: () -> [String], setter: () -> [String])
        }

        init(_ parameter: Parameter, _ typeName: TypeName, _ schemaProp: SchemaObjectProperty) {
            self.name = parameter
            self.typeName = typeName
            self.nullability = schemaProp.nullability
            self.accessor = .stored
        }

        init(name: String, typeName: TypeName, nullability: Nullability? = nil, accessor: Accessor) {
            self.name = name
            self.typeName = typeName
            self.nullability = nullability
            self.accessor = accessor
        }

        var isStored: Bool {
            switch self.accessor {
            case .stored:
                return true
            default:
                return false
            }
        }

        let name: String
        let typeName: String
        let nullability: Nullability?
        let accessor: Accessor

        var realTypeName: String {
            return nullability == .nullable ? "\(typeName)?" : typeName
        }

        var propertyName: String {
            return name.snakeCaseToPropertyName()
        }

        func render() -> [String] {

            switch accessor {
            case .stored:
                return ["let \(propertyName): \(self.realTypeName)"]
            case .readOnly(getter: let getter):
                return [
                    "var \(propertyName): \(self.realTypeName) {",
                    -->getter,
                    "}"
                ]
            case .computed(getter: let getter, setter: let setter):
                return [
                    "var \(propertyName): \(self.realTypeName) {",
                    -->self.renderAccessor(name: "get", body: getter),
                    -->self.renderAccessor(name: "set", body: setter),
                    "}"
                ]
            }
        }

        func renderAccessor(name: String, body: () -> [String]) -> [String] {
            return [
                "\(name) {",
                -->body,
                "}"
            ]
        }
    }

    indirect enum Root {
        case imports
        case category(
            className: String,
            categoryName: String,
            methods: [SwiftIR.Method],
            properties: [SwiftIR.Property]
        )
        case function(SwiftIR.Method)
        case classDecl(
            name: String,
            extends: String?,
            methods: [(MethodVisibility, SwiftIR.Method)],
            properties: [SwiftIR.Property],
            protocols: [String:[SwiftIR.Method]],
            enumRoots: [Root],
            adtRoots: [Root]
        )
        case enumDecl(name: String, values: EnumType)
        case adt(name: String, values: [(caseName: String, className: String)])

        func render() -> [String] {
            switch self {

            case .imports:
                return [
                    "import Foundation"
                    ]

            case .classDecl(let className, _, let methods, let properties, let protocols, let enumRoots, let adtRoots):
                let protocolList = protocols.keys.sorted().joined(separator: ", ")
                let protocolDeclarations = protocols.count > 0 ? ": \(protocolList)" : ""

                let enums = enumRoots.flatMap { $0.render() }
                let adts = adtRoots.flatMap { $0.render() }

                let methodsAndProtocolMethods = protocols.flatMap { $1 } + methods.map { $1 }

                return [
                    "struct \(className)\(protocolDeclarations) {",
                    -->adts,
                    -->enums,
                    properties.map { (prop) in
                        -->prop.render()
                    }.joined(separator: "\n").appending("\n"),
                    -->methodsAndProtocolMethods.flatMap { $0.render() },
                    "}"
                ]
            case .category(className: let className, categoryName: _, methods: _, properties: let properties):

                return  [
                    "extension \(className) {",
                    properties.map { (prop) in
                        -->prop.render()
                        }.joined(separator: "\n"),
                    "}"
                ]
            case .function(let method):
                return ["\(method.render())"]
            case .enumDecl(let name, let values):
                return [SwiftIR.enumStmt("\(name)\(values.rawSwiftType)") {
                    switch values {
                    case .integer(let options):
                        return options.map { "\(name + $0.camelCaseDescription) = \($0.defaultValue)" }
                    case .string(let options, _):
                        return options.map { "case \($0.defaultValue.snakeCaseToPropertyName()) = \($0.defaultValue.swiftLiteral())" }
                    }
                    }]

            case .adt(name: let name, values: let values):
                return [
                    SwiftIR.enumStmt("\(name)") {
                        values.map { "case \($0)(\($1))" }
                    }
                ]
            }
        }
    }
}
