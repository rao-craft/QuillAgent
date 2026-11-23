// swift-tools-version:6.0
// QuillAgent: a document written from an ask (a letter, a memo, a report, a resume, a proposal, a contract, a
// worksheet, a one-pager), laid out in pages and measured in WebKit, and written as PDF, Word, Pages, HTML and
// Markdown from one draft, as a Granite agent package. The host's model writes the words as blocks; the kit owns
// the page. An app that links the package finds the `quill` agent through Granite's roster, with nothing listed by hand.

import PackageDescription

let package = Package(
    name: "QuillAgent",
    // WebKit's WebPage lays the pages out and exports them in-process, with no window: macOS 26.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "QuillAgent", targets: ["QuillAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "QuillAgent",
            dependencies: [.product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "QuillAgentTests",
            dependencies: ["QuillAgent", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
