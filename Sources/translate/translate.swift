import Foundation
import ArgumentParser

@main
enum TranslateMain {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            await TranslateRunCommand.main(["--help"])
            return
        }

        await TranslateCommand.main(nil)
    }
}
