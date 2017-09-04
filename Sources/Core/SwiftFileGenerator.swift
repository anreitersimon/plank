//
//  SwiftFileGenerator.swift
//  plank
//
//  Created by anreitersimon on 9/3/17.
//
//

import Foundation
// MARK: File Generation Manager

struct SwiftFileGenerator: FileGeneratorManager {
    static func filesToGenerate(descriptor: SchemaObjectRoot, generatorParameters: GenerationParameters) -> [FileGenerator] {

        let rootsRenderer = SwiftModelRenderer(rootSchema: descriptor, params: generatorParameters)

        return [
            SwiftImplementationFile(roots: rootsRenderer.renderRoots(), className: rootsRenderer.className)
        ]
    }

    static func runtimeFiles() -> [FileGenerator] {
        return []
    }
}

fileprivate extension FileGenerator {
    var swiftDefaultIndent: Int {
        return 4
    }
}

struct SwiftImplementationFile: FileGenerator {
    let roots: [SwiftIR.Root]
    let className: String

    var fileName: String {
        return "\(className).swift"
    }

    var indent: Int {
        return swiftDefaultIndent
    }

    func renderFile() -> String {
        let output = (
            [self.renderCommentHeader()] +
                self.roots.map { $0.render().joined(separator: "\n") }
            )
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            .filter { $0 != "" }
            .joined(separator: "\n\n")
        return output
    }
}
