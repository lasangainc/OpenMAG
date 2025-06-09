//
//  OpenMAGApp.swift
//  OpenMAG
//
//  Created by Benji on 2025-06-04.
//

import SwiftUI
import AppKit

@main
struct OpenMAGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("OpenMAG", systemImage: "brain.head.profile") {
            ContentView()
                .background(Color.clear)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the dock but keep it as menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Configure window transparency after a short delay to ensure MenuBarExtra window exists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureWindow()
        }
    }
    
    private func configureWindow() {
        // Find the MenuBarExtra window
        for window in NSApp.windows {
            if window.className.contains("MenuBarExtra") || window.level == NSWindow.Level.statusBar {
                window.isOpaque = false
                window.backgroundColor = NSColor.clear
                window.hasShadow = false
                
                // Make the window background completely transparent
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                
                // Ensure content view background is clear
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                
                break
            }
        }
    }
    
    // Ensure app doesn't terminate when window closes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
