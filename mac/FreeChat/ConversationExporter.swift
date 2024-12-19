import AppKit

actor ConversationExporter {

  let conversation: Conversation

  init(conversation: Conversation) {
    self.conversation = conversation
  }

  @MainActor
  func showSavePanel() async throws -> URL {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    return try await withCheckedThrowingContinuation { continuation in
      panel.begin { result in
        if result == .OK, let panelURL = panel.url  {
          continuation.resume(returning: panelURL)
        } else {
          continuation.resume(throwing: ExportError.emptyURL)
        }
      }
    }
  }

  func exportMarkdown(url: URL) async throws {
    guard let messages = conversation.messages?.sortedArray(using: [.init(key: "createdAt", ascending: true)]) else { throw ExportError.emptyConversation }
    
    var lines = [String]()
    for case let message as Message in messages {
      guard
        let fromId = message.fromId?.replacingOccurrences(of: "^###\\s+", with: "", options: .regularExpression),
        let createdAt = message.createdAt?.formatted(date: .abbreviated, time: .shortened),
        let text = message.text
      else { continue }

      let template = """
      \(createdAt) \(fromId): 
      \(text)

      - - - - - - - - - - - - - - - - - -

      """
      lines.append(template)
    }

    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  enum ExportError: Error {
    case emptyURL
    case emptyConversation
  }
}
