
## CLI

https://github.com/apple/swift-argument-parser

See notes/Swift-Argument-Parser-Practical-Guide.md for tutorial.

## LLM

https://github.com/mattt/AnyLanguageModel/

It covers the main API providers and Apple Intelligence models.

Snippet:

```swift
let model = SystemLanguageModel.default
let session = LanguageModelSession(model: model)

// Set the system prompt
session.instructions = "You are a helpful assistant that speaks like a pirate."

let response = try await session.respond {
    Prompt("What's the weather like?")
}
print(response.content)
```

## String Catalog Translation

Use the local "/Users/atacan/Developer/Repositories/StringCatalogKit/" package.

See "/Users/atacan/Developer/Repositories/StringCatalogKit/README.md" for tutorial.  
It already has a LLM-based implementation where we can plug in the above LLM package methods: "/Users/atacan/Developer/Repositories/StringCatalogKit/Sources/CatalogTranslationLLM/LLMTranslator.swift"  
Example implementation can give you an idea: "/Users/atacan/Developer/Repositories/StringCatalogKit/examples/Sources/TranslateCatalogWithOpenAI/main.swift"

## TOML

https://github.com/LebJe/TOMLKit

