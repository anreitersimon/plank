//
//  SwiftFileRenderer.swift
//  plank
//
//  Created by anreitersimon on 9/3/17.
//
//

import Foundation

protocol SwiftFileRenderer {
    var rootSchema: SchemaObjectRoot { get }
    var params: GenerationParameters { get }

    func renderRoots() -> [SwiftIR.Root]
}

extension SwiftFileRenderer {
    // MARK: Properties

    var className: String {
        return self.rootSchema.className(with: self.params)
    }

    var parentDescriptor: Schema? {
        return self.rootSchema.extends.flatMap { $0.force() }
    }

    var properties: [(Parameter, SchemaObjectProperty)] {
        return self.rootSchema.properties.map { $0 }
    }

    var isBaseClass: Bool {
        return rootSchema.extends == nil
    }

    fileprivate func referencedClassNames(schema: Schema) -> [String] {
        switch schema {
        case .reference(with: let ref):
            switch ref.force() {
            case .some(.object(let schemaRoot)):
                return [schemaRoot.className(with: self.params)]
            default:
                fatalError("Bad reference found in schema for class: \(self.className)")
            }
        case .object(let schemaRoot):
            return [schemaRoot.className(with: self.params)]
        case .map(valueType: .some(let valueType)):
            return referencedClassNames(schema: valueType)
        case .array(itemType: .some(let itemType)):
            return referencedClassNames(schema: itemType)
        case .oneOf(types: let itemTypes):
            return itemTypes.flatMap(referencedClassNames)
        default:
            return []
        }
    }

    func renderReferencedClasses() -> Set<String> {
        return Set(rootSchema.properties.values.map { $0.schema }.flatMap(referencedClassNames))
    }

    func swiftClassFromSchema(_ param: String, _ schema: Schema) -> String {

        switch schema {
        case .array(itemType: .none):
            return "[Any]"
        case .array(itemType: .some(let itemType)):
            return "[\(swiftClassFromSchema(param, itemType))]"
        case .map(valueType: .none):
            return "[String: Any]"
        case .map(valueType: .some(let valueType)):
            return "[String: \(swiftClassFromSchema(param, valueType))]"
        case .string(format: .none),
             .string(format: .some(.email)),
             .string(format: .some(.hostname)),
             .string(format: .some(.ipv4)),
             .string(format: .some(.ipv6)):
            return "String"
        case .string(format: .some(.dateTime)):
            return "Date"
        case .string(format: .some(.uri)):
            return "URL"
        case .integer:
            return "Int"
        case .float:
            return "Double"
        case .boolean:
            return "Bool"
        case .enumT:
            return swiftEnumTypeName(propertyName: param, className: className)
        case .object(let objSchemaRoot):
            return "\(objSchemaRoot.className(with: params))"
        case .reference(with: let ref):
            switch ref.force() {
            case .some(.object(let schemaRoot)):
                return swiftClassFromSchema(param, .object(schemaRoot))
            default:
                fatalError("Bad reference found in schema for class: \(className)")
            }
        case .oneOf(types:_):
            return "\(className)\(param.snakeCaseToCamelCase())"
        }
    }
}
