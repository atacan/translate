import Foundation
import ArgumentParser

@main
enum TranslateMain {
    static func main() async {
        await TranslateCommand.main(nil)
    }
}
