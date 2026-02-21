---
title: Swift Argument Parser Practical Guide
date: 2026-02-07
app: blissum
language: en
isPublished: true
summary: A practical reference for Swift Argument Parser covering @Option, @Argument, AsyncParsableCommand, and custom argument parsing types.
---


### 1. How to use `@Option` with custom `ExpressibleByArgument` types (enums from strings)

**Protocol Requirements:**
The `ExpressibleByArgument` protocol requires implementing:
- `init?(argument: String)` - initializes from a string argument
- `var defaultValueDescription: String` - description for help text
- `static var allValueStrings: [String]` - list of all possible values
- `static var allValueDescriptions: [String: String]` - descriptions for each value

**For RawRepresentable Enums** (easiest approach):
The library provides a default implementation for `RawRepresentable` types like string-backed enums. You only need to declare conformance:

```swift
enum ReleaseMode: String, ExpressibleByArgument {
    case debug, release
}

struct Example: ParsableCommand {
    @Option var mode: ReleaseMode
}
```

Color Example from the codebase:
https://github.com/apple/swift-argument-parser/blob/main/Examples/color/Color.swift

```swift
enum ColorOptions: String, CaseIterable, ExpressibleByArgument {
    case red
    case blue
    case yellow

    public var defaultValueDescription: String {
        switch self {
        case .red: return "A red color."
        case .blue: return "A blue color."
        case .yellow: return "A yellow color."
        }
    }

    public var description: String {
        switch self {
        case .red: return "A red color."
        case .blue: return "A blue color."
        case .yellow: return "A yellow color."
        }
    }
}

struct Color: ParsableCommand {
    @Option(help: "Your favorite color.")
    var fav: ColorOptions
}
```

**For Custom Types:**
Implement `ExpressibleByArgument` directly:

```swift
struct Path: ExpressibleByArgument {
    var pathString: String

    init?(argument: String) {
        self.pathString = argument
    }
}
```

### 2. How to make optional options (parameters that may or may not be provided)

Using Optional types:
Options with `Optional` types implicitly default to `nil`:

```swift
@Option var secondColor: ColorOptions? = nil  // Optional
@Option var count: Int?                        // Also optional (nil default)
```

From the Repeat example:
```swift
@Option(help: "How many times to repeat 'phrase'.")
var count: Int? = nil
```

In Color example:
```swift
@Option(
    help: .init("Your second favorite color.", discussion: "This is optional."))
var second: ColorOptions?
```

### 3. How to use `@Argument` for positional arguments

Basic required argument:
```swift
@Argument var phrase: String  // Required
```

Optional argument with default:
```swift
@Argument var greeting: String = "Hello"  // Optional with default
@Argument var inputFile: URL?              // Optional
```

Array of arguments:
```swift
@Argument var files: [String] = []
```

From CountLines example:
```swift
@Argument(
    help: "A file to count lines in. If omitted, counts the lines of stdin.",
    completion: .file(), 
    transform: URL.init(fileURLWithPath:))
var inputFile: URL? = nil
```

From Math example:
```swift
@Argument(help: "A group of integers to operate on.")
var values: [Int] = []
```

### 4. How to set up command configuration (name, abstract, discussion)

Using `CommandConfiguration`:
https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Documentation.docc/Extensions/CommandConfiguration.md

```swift
static let configuration = CommandConfiguration(
    commandName: "stats",           // Optional: override command name
    abstract: "Calculate statistics.",
    discussion: "More detailed explanation here",
    usage: "Custom usage string",
    version: "1.0.0",              // Adds --version support
    subcommands: [Average.self, StandardDeviation.self],
    defaultSubcommand: Average.self,
    helpNames: [.long, .short],
    aliases: ["st", "stats-cmd"]
)
```

From Math example:
```swift
struct Math: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A utility for performing maths.",
        version: "1.0.0",
        subcommands: [Add.self, Multiply.self, Statistics.self],
        defaultSubcommand: Add.self)
}

struct Add: ParsableCommand {
    static let configuration =
        CommandConfiguration(abstract: "Print the sum of the values.")
}

struct Multiply: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the product of the values.",
        aliases: ["mul"])
}
```

### 5. How to use `AsyncParsableCommand` for async operations

Steps to implement:
1. Declare conformance to `AsyncParsableCommand` (instead of `ParsableCommand`)
2. Apply the `@main` attribute to the root command
3. Mark the `run()` method as `async`

From CountLines example:
```swift
@main
@available(macOS 12, iOS 15, visionOS 1, tvOS 15, watchOS 8, *)
struct CountLines: AsyncParsableCommand {
    @Argument(
        help: "A file to count lines in. If omitted, counts the lines of stdin.",
        completion: .file(), 
        transform: URL.init(fileURLWithPath:))
    var inputFile: URL? = nil

    @Option(help: "Only count lines with this prefix.")
    var prefix: String? = nil

    @Flag(help: "Include extra information in the output.")
    var verbose = false

    var fileHandle: FileHandle {
        get throws {
            guard let inputFile else {
                return .standardInput
            }
            return try FileHandle(forReadingFrom: inputFile)
        }
    }

    mutating func run() async throws {
        var lineCount = 0
        for try await line in try fileHandle.bytes.lines {
            if let prefix {
                lineCount += line.starts(with: prefix) ? 1 : 0
            } else {
                lineCount += 1
            }
        }
        printCount(lineCount)
    }
}
```

### 6. How to handle arrays/repeated options (e.g., `--custom-vocabulary word1 --custom-vocabulary word2`)

Array parsing strategies:

```swift
// Default: parse one value per option, repeat option multiple times
@Option var files: [String] = []
// Usage: command --files file1.swift --files file2.swift

// Parse multiple values up to next option
@Option(parsing: .upToNextOption) var files: [String]
// Usage: command --files file1.swift file2.swift

// Unconditional single value (can capture dash-prefixed values)
@Option(parsing: .unconditionalSingleValue) var files: [String]
// Usage: command --files file1.swift --files --verbose

// Remaining: capture all remaining values
@Option(parsing: .remaining) var passthrough: [String]
// Usage: command --passthrough --foo 1 --bar 2
```

From the DeclaringArguments documentation:
```swift
struct Example: ParsableCommand {
    @Option(parsing: .upToNextOption) var files: [String] = []
    @Flag var verbose = false

    mutating func run() {
        print("Verbose: \\(verbose), files: \\(files)")
    }
}
```

Usage examples:
```bash
$ example --file file1.swift file2.swift
Verbose: false, files: ["file1.swift", "file2.swift"]

$ example --file file1.swift file2.swift --verbose
Verbose: true, files: ["file1.swift", "file2.swift"]
```

### 7. How `ExpressibleByArgument` protocol works for custom types

Protocol Definition:
[https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable Types/ExpressibleByArgument.swift](https://github.com/apple/swift-argument-parser/blob/main/blob/main/Sources/ArgumentParser/Parsable%20Types/ExpressibleByArgument.swift)

The protocol has 4 requirements:

```swift
public protocol ExpressibleByArgument: _SendableMetatype {
    /// Creates from a command-line string
    init?(argument: String)

    /// Description shown as default value in help
    var defaultValueDescription: String { get }

    /// All possible string values (for help display)
    static var allValueStrings: [String] { get }

    /// Descriptions for each possible value
    static var allValueDescriptions: [String: String] { get }

    /// Default completion kind for shell completions
    static var defaultCompletionKind: CompletionKind { get }
}
```

Default Implementations:

1. **RawRepresentable types** - automatic implementation:
   - The library automatically generates `init?(argument:)` for `RawRepresentable` types
   - Only declare conformance: `enum Mode: String, ExpressibleByArgument {}`

2. **CaseIterable types** - automatic list generation:
   - `allValueStrings` automatically returns all case names
   - `defaultCompletionKind` returns `.list(allValueStrings)`

3. **Standard library types** - already conform:
   - Int, Int8-64, UInt, UInt8-64
   - Float, Double
   - Bool
   - String

Custom Implementation Example:
```swift
struct CustomPath: ExpressibleByArgument {
    var path: String

    init?(argument: String) {
        guard !argument.isEmpty else { return nil }
        self.path = argument
    }

    var defaultValueDescription: String {
        path
    }
}
```

Transform Functions Alternative:
For complex types you don't own, use `transform` closures:

```swift
enum Format {
    case text
    case other(String)

    init(_ string: String) throws {
        if string == "text" {
            self = .text
        } else {
            self = .other(string)
        }
    }
}

struct Example: ParsableCommand {
    @Argument(transform: Format.init)
    var format: Format
}
```

### Additional Useful Features

Validation:
https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Documentation.docc/Articles/Validation.md

```swift
struct Select: ParsableCommand {
    @Option var count: Int = 1
    @Argument var elements: [String] = []

    mutating func validate() throws {
        guard count >= 1 else {
            throw ValidationError("Please specify a 'count' of at least 1.")
        }

        guard !elements.isEmpty else {
            throw ValidationError("Please provide at least one element.")
        }

        guard count <= elements.count else {
            throw ValidationError("Count cannot exceed number of elements.")
        }
    }

    mutating func run() {
        print(elements.shuffled().prefix(count).joined(separator: "\n"))
    }
}
```

Option Groups:
Share options across multiple commands:

```swift
struct Options: ParsableArguments {
    @Flag(name: [.customLong("hex-output"), .customShort("x")])
    var hexadecimalOutput = false

    @Argument var values: [Int] = []
}

struct Add: ParsableCommand {
    @OptionGroup var options: Options

    mutating func run() {
        let result = options.values.reduce(0, +)
        print(result)
    }
}
```

Name Customization:
```swift
@Flag(name: .long)              // Use property name as long flag
@Flag(name: .short)             // Use first letter as short flag
@Option(name: .customLong("count"))
@Option(name: [.customShort("I"), .long])
@Flag(name: .shortAndLong)      // Both short and long names
```

All of this information comes from the following key files in the swift-argument-parser repository:
- https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Documentation.docc/Articles/DeclaringArguments.md
- https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable Types/ExpressibleByArgument.swift
- https://github.com/apple/swift-argument-parser/blob/main/Examples/ (color, repeat, math, count-lines)
- [https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable Properties/Option.swift](https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable%20Properties/Option.swift)
- [https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable Properties/Argument.swift](https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable%20Properties/Argument.swift)
