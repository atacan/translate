// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "translate",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/mattt/AnyLanguageModel.git", from: "0.7.1"),
        .package(url: "https://github.com/atacan/UsefulThings.git", branch: "main"),
        .package(url: "https://github.com/atacan/DeepLAPI.git", branch: "main"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.1.0"),
        .package(path: "../StringCatalogKit"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/davbeck/swift-glob.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "translate",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                .product(name: "StringCatalog", package: "StringCatalogKit"),
                .product(name: "CatalogTranslation", package: "StringCatalogKit"),
                .product(name: "CatalogTranslationLLM", package: "StringCatalogKit"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Glob", package: "swift-glob"),
                .product(name: "UsefulThings", package: "UsefulThings"),
                .product(name: "DeepLAPI", package: "DeepLAPI"),
                .product(name: "DeepLAPITypes", package: "DeepLAPI"),
                .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
            ]
        ),
        .testTarget(
            name: "translateTests",
            dependencies: ["translate"]
        ),
    ]
)
