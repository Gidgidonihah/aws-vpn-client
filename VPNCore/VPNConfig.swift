import Foundation

public struct VPNConfig: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let fileURL: URL

    public init(fileURL: URL) {
        self.id = UUID()
        self.fileURL = fileURL
        self.name = fileURL.deletingPathExtension().lastPathComponent
    }
}
