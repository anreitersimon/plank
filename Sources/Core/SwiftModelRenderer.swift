//
//  SwiftModelRenderer.swift
//  plank
//
//  Created by anreitersimon on 9/3/17.
//
//

import Foundation

public struct SwiftModelRenderer: SwiftFileRenderer {
    let rootSchema: SchemaObjectRoot
    let params: GenerationParameters

    init(rootSchema: SchemaObjectRoot, params: GenerationParameters) {
        self.rootSchema = rootSchema
        self.params = params
    }

    var swiftProperties: [SwiftIR.Property] {
        return properties
            .map { param, prop in SwiftIR.Property(param, swiftClassFromSchema(param, prop.schema), prop)
        }
    }

    // MARK: Model methods

    func renderClassName() -> SwiftIR.Property {
        return SwiftIR.Property(
            name: "className",
            typeName: "String",
            accessor: .readOnly(getter: {
                ["return \(self.className.swiftLiteral())"]
            })
        )
    }

    func renderPolymorphicTypeIdentifier() -> SwiftIR.Property {
        return SwiftIR.Property(
            name: "jsonSchemaId",
            typeName: "String",
            accessor: .readOnly(getter: {
                ["return \(self.rootSchema.typeIdentifier.swiftLiteral())"]
            })
        )
    }

    func renderJsonInitializer() -> SwiftIR.Method {
        return SwiftIR.method("init(_ json: JSON) throws") {
            self.properties
                .flatMap { (param, prop) in
                    renderPropertyInitializer(param, prop)
            }
        }
    }
    
    func adtRootsForSchema(property: String, schemas: [SchemaObjectProperty]) -> [SwiftIR.Root] {
        let adtName = property.snakeCaseToPropertyName().uppercaseFirst
        
        let values: [(caseName: String, className: String)] = schemas.map { (prop) in
            
            let className = self.swiftClassFromSchema(property, prop.schema)
            return (className.snakeCaseToPropertyName(), className)
        }
        
        return [SwiftIR.Root.adt(
            name: adtName,
            values: values
            )]
        
    }

    func renderPropertyInitializer(_ parameter: Parameter, _ prop: SchemaObjectProperty) -> [String] {
        let property = SwiftIR.Property(parameter, swiftClassFromSchema(parameter, prop.schema), prop)

        guard property.isStored else { return [] }

        if property.typeName == "Date" {
            return [
                "self.\(property.propertyName) = try json.date(\"\(property.name)\", formatter: .backend)"
            ]
        }

        return [
            "self.\(property.propertyName) = try json.value(\"\(property.name)\")"
        ]

    }

    func renderRoots() -> [SwiftIR.Root] {
        let properties: [(Parameter, SchemaObjectProperty)] = rootSchema.properties.map { $0 } // Convert [String:Schema] -> [(String, Schema)]

        let protocols: [String : [SwiftIR.Method]] = [
            "JsonInitializable": [renderJsonInitializer()]
        ]

        func resolveClassName(_ schema: Schema?) -> String? {
            switch schema {
            case .some(.object(let root)):
                return root.className(with: self.params)
            case .some(.reference(with: let ref)):
                return resolveClassName(ref.force())
            default:
                return nil
            }
        }

        let parentName = resolveClassName(self.parentDescriptor)
        let enumRoots = self.properties.flatMap { (param, prop) -> [SwiftIR.Root] in
            switch prop.schema {
            case .enumT(let enumValues):
                return [SwiftIR.Root.enumDecl(
                    name: swiftClassFromSchema(param, prop.schema),
                    values: enumValues)]
            default: return []
            }
        }

        // TODO: Synthesize oneOf ADT Classes and Class Extension
        // TODO (rmalik): Clean this up, too much copy / paste here to support oneOf cases
        let adtRoots = self.properties.flatMap { (param, prop) -> [SwiftIR.Root] in
            switch prop.schema {
            case .oneOf(types: let possibleTypes):
                let objProps = possibleTypes.map { SchemaObjectProperty(schema: $0, nullability: $0.isObjCPrimitiveType ? nil : .nullable)}
                return adtRootsForSchema(property: param, schemas: objProps)
            case .array(itemType: .some(let itemType)):
                switch itemType {
                case .oneOf(types: let possibleTypes):
                    let objProps = possibleTypes.map { SchemaObjectProperty(schema: $0, nullability: $0.isObjCPrimitiveType ? nil : .nullable)}
                    return adtRootsForSchema(property: param, schemas: objProps)
                default: return []
                }
            case .map(valueType: .some(let additionalProperties)):
                switch additionalProperties {
                case .oneOf(types: let possibleTypes):
                    let objProps = possibleTypes.map { SchemaObjectProperty(schema: $0, nullability: $0.isObjCPrimitiveType ? nil : .nullable)}
                    return adtRootsForSchema(property: param, schemas: objProps)
                default: return []
                }
            default: return []
            }
        }

        return [
                SwiftIR.Root.imports,
                SwiftIR.Root.classDecl(
                    name: self.className,
                    extends: parentName,
                    methods: [],
                    properties: properties.map { param, prop in
                        SwiftIR.Property(param, swiftClassFromSchema(param, prop.schema), prop) },
                    protocols: protocols,
                    enumRoots: enumRoots,
                    adtRoots: adtRoots
                )
        ]
    }
}
