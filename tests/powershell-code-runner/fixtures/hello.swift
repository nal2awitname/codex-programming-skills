import Foundation

print("OK:" + CommandLine.arguments.dropFirst().joined(separator: "|"))
exit(3)
