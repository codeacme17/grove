import Foundation

let file = URL(fileURLWithPath: CommandLine.arguments[1])
let bookmark = try file.bookmarkData(options: [.suitableForBookmarkFile, .withoutImplicitSecurityScope],
                                     includingResourceValuesForKeys: nil, relativeTo: nil)
FileHandle.standardOutput.write(bookmark)
