//
//  MantrasApp.swift
//  Mantras
//
//  Created by Peter Sugihara on 7/31/23.
//

import SwiftUI
import KeyboardShortcuts

@main
struct FreeChatApp: App {
  @NSApplicationDelegateAdaptor(FreeChatAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) var openWindow
  @StateObject var conversationManager = ConversationManager.shared
  @State var keyWindowID: String?

  let persistenceController = PersistenceController.shared

  var body: some Scene {
    Window(Text("FreeChat"), id: "main") {
      ContentView()
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .environmentObject(conversationManager)
        .onAppear {
          NSWindow.allowsAutomaticWindowTabbing = false
          let _ = NSApplication.shared.windows.map { $0.tabbingMode = .disallowed }
        }
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Chat") {
          conversationManager.newConversation(viewContext: persistenceController.container.viewContext, openWindow: openWindow)
        }.keyboardShortcut(KeyboardShortcut("N"))
     }
      CommandGroup(after: .newItem) {
        Button("Export...") {
          Task {
            let exporter = ConversationExporter(conversation: conversationManager.currentConversation)
            do {
              let exportURL = try await exporter.showSavePanel()
              try await exporter.exportMarkdown(url: exportURL)
            } catch {
              print("Error exporting conversation: \(error)")
            }
          }
        }
        .keyboardShortcut(KeyboardShortcut("E"))
        .disabled(keyWindowID != "main")
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { output in
          keyWindowID = (output.object as? NSWindow)?.identifier?.rawValue
        }
      }
      SidebarCommands()
      CommandGroup(after: .windowList, addition: {
        Button("Conversations") {
          conversationManager.bringConversationToFront(openWindow: openWindow)
        }.keyboardShortcut(KeyboardShortcut("0"))
      })
    }


#if os(macOS)
    Settings {
      SettingsView()
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .environmentObject(conversationManager)
    }
    .windowResizability(.contentSize)
#endif
  }
}
