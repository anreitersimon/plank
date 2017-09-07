//
//  SchemaLoader.swift
//  Plank
//
//  Created by Andrew Chun on 6/17/16.
//  Copyright © 2016 Rahul Malik. All rights reserved.
//

import Foundation

protocol SchemaLoader {
    var refUrls: [URL] { get }
    
    func loadSchema(_ schemaUrl: URL) -> Schema
}

class FileSchemaLoader: SchemaLoader {
    var refUrls: [URL] = []

    static let sharedInstance = FileSchemaLoader()
    static let sharedPropertyLoader = Schema.propertyFunctionForType(loader: FileSchemaLoader.sharedInstance)
    var refs: [URL:Schema]

    init() {
        self.refs = [URL: Schema]()
    }

    func loadSchema(_ schemaUrl: URL) -> Schema {
        if let cachedValue = refs[schemaUrl] {
            return cachedValue
        }

        // Load from local file
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: schemaUrl.path))  else {
            fatalError("Error loading or parsing schema at URL: \(schemaUrl)")
        }

        guard let jsonResult = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) else {
            fatalError("Invalid JSON. Unable to parse json at URL: \(schemaUrl)")
        }

        guard let jsonDict = jsonResult as? JSONObject else {
            fatalError("Invalid Schema. Expected dictionary as the root object type for schema at URL: \(schemaUrl)")
        }

        let id = jsonDict["id"] as? String ?? ""
        guard id.hasSuffix(schemaUrl.lastPathComponent) == true else {
            fatalError("Invalid Schema: The value for the `id` (\(id) must end with the filename \(schemaUrl.lastPathComponent).")
        }

        guard let schema = FileSchemaLoader.sharedPropertyLoader(jsonDict, schemaUrl) else {
            fatalError("Invalid Schema. Unable to parse schema at URL: \(schemaUrl)")
        }

        refs[schemaUrl] = schema
        return schema
    }
}

class SwaggerSchemaLoader: SchemaLoader {

    let rootUrl: URL
    let definitions: [String: JSONObject]
    
    var refUrls: [URL] {
        return definitions
            .map { $0.key }
            .map { self.rootUrl.appendingPathComponent($0) }
    }
    
    var refs: [URL:Schema]

    init(rootUrl: URL) {
        self.rootUrl = rootUrl
        self.refs = [URL: Schema]()
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: rootUrl.path))  else {
            fatalError("Error loading or parsing schema at URL: \(rootUrl)")
        }
        
        
        guard let jsonResult = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) else {
            fatalError("Invalid JSON. Unable to parse json at URL: \(rootUrl)")
        }
        
        guard let jsonDict = jsonResult as? JSONObject else {
            fatalError("Invalid Schema. Expected dictionary as the root object type for schema at URL: \(rootUrl)")
        }
        
        let definitionsDict: JSONObject = jsonDict["definitions"] as? JSONObject
            ?? [:]
        
        var defs: [String: JSONObject] = [:]
        
        for (key, value) in definitionsDict {
            defs[key] = value as? JSONObject
        }
        
        self.definitions = defs
    }

    func path(schemaUrl: URL) -> String? {
        let path = schemaUrl.path
        let rootPath = "\(self.rootUrl.path)/"
        
        if path.hasPrefix(rootPath) {
            
            let index = path.index(after: rootPath.endIndex)
            
            return path.substring(from: index)
        }

        return nil
    }

    func loadSchema(_ schemaUrl: URL) -> Schema {
        guard let path = self.path(schemaUrl: schemaUrl) else {
            fatalError("Could not extract path from URL: \(schemaUrl)")
        }

        if let cachedValue = refs[schemaUrl] {
            return cachedValue
        }

        guard let jsonDict = definitions[path] else {
            fatalError("Invalid Schema. Expected dictionary as the root object type for schema at URL: \(schemaUrl)")
        }
        
        let propertyFunction = Schema.propertyFunctionForType(loader: self)

        guard let schema = propertyFunction(jsonDict, schemaUrl) else {
            
            print(schemaUrl)
            
            fatalError("Invalid Schema. Unable to parse schema at URL: \(schemaUrl)")
        }

        refs[schemaUrl] = schema
        return schema
    }
}
