//
//  OllamaBackend.swift
//  FreeChat
//

import Foundation
import EventSource

actor OllamaBackend {

  struct RoleMessage: Codable {
    let role: String
    let content: String
  }
  
  struct CompleteParams: Encodable {
    let messages: [RoleMessage]
    let model: String
    let stream = true

    func toJSON() -> String {
      let encoder = JSONEncoder()
      let jsonData = try? encoder.encode(self)
      return String(data: jsonData!, encoding: .utf8)!
    }
  }

  struct Response: Decodable {
    struct Choice: Decodable {
      let index: Int
      let delta: RoleMessage
      let finishReason: String?
    }
    let id: String
    let object: String
    let created: Int
    let model: String
    let systemFingerprint: String
    let choices: [Choice]
  }

  private var interrupted = false

  private let contextLength: Int
  private let scheme: String
  private let host: String
  private let port: String

  init(contextLength: Int, tls: Bool, host: String, port: String) {
    self.contextLength = contextLength
    self.scheme = tls ? "https" : "http"
    self.host = host
    self.port = port
  }

  func complete(messages: [String]) throws -> AsyncStream<String> {
    let messages = [RoleMessage(role: "system", content: "you know")]
      + messages.map({ RoleMessage(role: "user", content: $0) })
    let params = CompleteParams(messages: messages, model: "orca-mini")
    let url = URL(string: "\(scheme)://\(host):\(port)/v1/chat/completions")!
    let request = buildRequest(url: url, params: params)

    return AsyncStream<String> { continuation in
      Task.detached {
        let eventSource = EventSource(request: request)
        eventSource.connect()

      L: for await event in eventSource.events {
          guard await !self.interrupted else { break L }
          switch event {
          case .open: continue
          case .error(let error):
            print("ollama EventSource server error:", error.localizedDescription)
            break L
          case .message(let message):
            if let response = try await self.decodeCompletionMessage(message: message.data),
               let choice = response.choices.first {
              continuation.yield(choice.delta.content)
              if choice.finishReason != nil { break L }
            }
          case .closed:
            print("ollama EventSource closed")
            break L
          }
        }

        await eventSource.close()
        continuation.finish()
      }
    }
  }

  func interrupt() async { interrupted = true }

  func buildRequest(url: URL, params: CompleteParams) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("keep-alive", forHTTPHeaderField: "Connection")
    request.setValue("Bearer: none", forHTTPHeaderField: "Authorization")
    request.httpBody = params.toJSON().data(using: .utf8)

    return request
  }

  private func decodeCompletionMessage(message: String?) throws -> Response? {
    guard let data = message?.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Response.self, from: data)
  }
}
