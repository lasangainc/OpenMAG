//
//  ContentView.swift
//  OpenMAG
//
//  Created by Benji on 2025-06-04.
//

import SwiftUI
import QuickLookThumbnailing
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var isTransforming = false
    
    var body: some View {
        ZStack {
            // Completely transparent background
            Color.clear
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Invisible header with close button
                HStack {
                    Spacer()
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .opacity(0.6) // Make close button subtle
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Chat Container (Input + Response) - Positioned at top
                VStack(spacing: 12) {
                    // Siri-style Input Field
                    ZStack {
                        // Siri-style pill input background with transparency
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            .frame(height: 45)
                            .frame(width: 320) // Fixed width for input
                            .scaleEffect(isTransforming ? 1.02 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isTransforming)
                        
                        HStack(spacing: 12) {
                            // Left icon
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            // Input text
                            ZStack(alignment: .leading) {
                                if chatViewModel.currentInput.isEmpty {
                                    Text(chatViewModel.hasValidAPIKey() ? "Describe a task for your Mac..." : "Enter API key in settings")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 15))
                                }
                                
                                // Invisible TextField
                                TextField("", text: $chatViewModel.currentInput)
                                    .font(.system(size: 15))
                                    .focused($isInputFocused)
                                    .textFieldStyle(.plain)
                                    .disabled(!chatViewModel.hasValidAPIKey() || chatViewModel.isLoading) // Disable while loading
                                    .onSubmit {
                                        sendMessageWithAnimation()
                                    }
                            }
                            
                            Spacer()
                            
                            // Right icon (Send/Settings/Loading)
                            Button(action: {
                                if chatViewModel.isLoading {
                                    // Do nothing while loading
                                    return
                                } else if !chatViewModel.currentInput.isEmpty && chatViewModel.hasValidAPIKey() {
                                    sendMessageWithAnimation()
                                } else {
                                    // Show settings when input is empty OR no API key
                                    chatViewModel.showSettings = true
                                }
                            }) {
                                if chatViewModel.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                } else if !chatViewModel.currentInput.isEmpty && chatViewModel.hasValidAPIKey() {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(chatViewModel.isLoading)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Response Pills Stack (User and Bot Messages)
                    // The message limit was removed in ViewModel, so this will show more history now.
                    VStack(spacing: 8) {
                        ForEach(Array(chatViewModel.messages.enumerated()), id: \.element.id) { index, message in
                            SiriPillView(chatViewModel: chatViewModel, message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 30) // Center the content
                
                Spacer()
            }
            
            // Settings overlay
            if chatViewModel.showSettings {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        chatViewModel.showSettings = false
                    }
                
                SettingsView(
                    chatViewModel: chatViewModel,
                    isPresented: $chatViewModel.showSettings
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 380, height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 25.0))
        .background(Color.clear) 
        .onAppear {
            if chatViewModel.hasValidAPIKey() {
                isInputFocused = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chatViewModel.showSettings)
    }
    
    private func sendMessageWithAnimation() {
        guard !chatViewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard chatViewModel.hasValidAPIKey() else {
            chatViewModel.showSettings = true
            return
        }
        guard !chatViewModel.isLoading else { return } // Prevent sending while already processing
        
        isTransforming = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            chatViewModel.sendMessage()
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isTransforming = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
}

struct SiriPillView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    let message: ChatMessage
    @State private var isVisible = false
    @State private var isTextExpanded = false

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // Main message text or initial confirmation text
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // Only show icon for user messages (empty space for AI messages)
                    if message.isUser {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        // Empty space for AI messages (no icon)
                        Spacer()
                            .frame(width: 0)
                    }

                    VStack(spacing: 8) {
                        Text(message.text)
                            .font(.system(size: 15))
                            .foregroundColor(message.isUser ? .white : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(hasFileCarousel && !isTextExpanded ? 2 : nil)
                            .frame(minWidth: 60, maxWidth: 250)
                            .padding(.vertical, 14)
                        
                        // Show more/less button when carousel is present and text is long
                        if hasFileCarousel && isLongText {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isTextExpanded.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(isTextExpanded ? "Show less" : "Show more")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.blue)
                                    
                                    Image(systemName: isTextExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 4)
                        }
                    }

                    // Right spacer to balance layout
                    if message.isUser {
                        Spacer()
                            .frame(width: 0)
                    } else {
                        Spacer()
                            .frame(width: 0)
                    }
                }
                .padding(.horizontal, 16)
                
                // File preview carousel - NOW INSIDE the AI response bubble
                if message.showFileCarousel && !message.files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(message.files) { file in
                                FilePreviewCard(file: file)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 80)
                    .padding(.bottom, 12) // Add some bottom padding within the bubble
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        message.isUser ? AnyShapeStyle(Color.blue) : 
                        AnyShapeStyle(LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            )

            // Conditional section for command confirmation
            if message.isConfirmationRequest && !message.isActioned {
                if let command = message.commandDetails {
                    Text(command)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(10)
                        .frame(maxWidth: 280) // Keep command display tidy
                        .padding(.top, 4)
                }
                
                // Show explanation if expanded
                if message.isExplanationExpanded, let explanation = message.commandExplanation {
                    Text(explanation)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .frame(maxWidth: 280)
                        .padding(.top, 4)
                }

                HStack(spacing: 12) {
                    Button("Accept") {
                        chatViewModel.confirmAndExecuteCommand(messageId: message.id)
                        // The assistant will then call run_terminal_cmd
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button(message.commandExplanation != nil && message.isExplanationExpanded ? "Hide" : "Explain") {
                        chatViewModel.explainCommand(messageId: message.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button("Reject") {
                        chatViewModel.rejectCommand(messageId: message.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.top, 8)
            }
        }
        .scaleEffect(isVisible ? 1.0 : 0.7)
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: isVisible ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
    
    // Simplified computed properties
    private var hasFileCarousel: Bool {
        return message.showFileCarousel && !message.files.isEmpty
    }
    
    private var isLongText: Bool {
        return message.text.count > 80 // Lowered threshold for testing
    }
}

struct FilePreviewCard: View {
    let file: FileInfo
    @State private var previewImage: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 4) {
            // File preview/thumbnail - transparent background
            ZStack {
                if let previewImage = previewImage {
                    // Show actual file preview
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if isLoading {
                    // Loading state - minimal styling
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.gray)
                        .frame(width: 60, height: 50)
                } else {
                    // Fallback to system/colored icon - no background
                    Image(systemName: fileTypeIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(fileTypeColor)
                        .frame(width: 60, height: 50)
                }
            }
            
            // File name
            Text(file.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
        .onAppear {
            loadFilePreview()
        }
    }
    
    private func loadFilePreview() {
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = generateFilePreview()
            DispatchQueue.main.async {
                self.previewImage = preview
                self.isLoading = false
            }
        }
    }
    
    private func generateFilePreview() -> NSImage? {
        let fileURL = URL(fileURLWithPath: file.fullPath)
        
        // For folders, always use SF Symbol - return nil to use fallback
        if file.fileType == .folder {
            return nil
        }
        
        // For images, try to load actual preview first
        if file.fileType == .image {
            if let imagePreview = loadImagePreview(from: fileURL) {
                return imagePreview
            }
        }
        
        // For documents, try QuickLook (but don't rely on it)
        if file.fileType == .document || file.fileType == .code {
            if let quickLookPreview = loadDocumentPreview(from: fileURL) {
                return quickLookPreview
            }
        }
        
        // For non-folders, try to get system file icon
        return getSystemFileIcon()
    }
    
    private func getSystemFileIcon() -> NSImage? {
        // This method now only handles non-folder files
        
        // First, try with the exact file path if file exists
        if FileManager.default.fileExists(atPath: file.fullPath) {
            let systemIcon = NSWorkspace.shared.icon(forFile: file.fullPath)
            if systemIcon.isValid && systemIcon.size.width > 0 {
                return systemIcon
            }
        }
        
        // Second, try with just the filename to get the file type icon
        let tempURL = URL(fileURLWithPath: file.name)
        let fileExtension = tempURL.pathExtension.lowercased()
        
        if !fileExtension.isEmpty {
            // Get icon based on file extension
            if #available(macOS 11.0, *) {
                // Modern approach using UTType
                if let utType = UTType(filenameExtension: fileExtension) {
                    let systemIcon = NSWorkspace.shared.icon(for: utType)
                    if systemIcon.isValid && systemIcon.size.width > 0 {
                        return systemIcon
                    }
                }
            }
            
            // Fallback: create a temporary file to get the icon
            let tempDir = NSTemporaryDirectory()
            let tempFilePath = tempDir + "temp_icon_file." + fileExtension
            
            // Create empty temp file if it doesn't exist
            if !FileManager.default.fileExists(atPath: tempFilePath) {
                FileManager.default.createFile(atPath: tempFilePath, contents: Data(), attributes: nil)
            }
            
            let tempIcon = NSWorkspace.shared.icon(forFile: tempFilePath)
            if tempIcon.isValid && tempIcon.size.width > 0 {
                return tempIcon
            }
        }
        
        // Final fallback based on file type
        return getFallbackIcon()
    }
    
    private func getFallbackIcon() -> NSImage? {
        // This method now only handles non-folder files
        switch file.fileType {
        case .image:
            if #available(macOS 11.0, *) {
                return NSWorkspace.shared.icon(for: .image)
            } else {
                return NSWorkspace.shared.icon(forFileType: "public.image")
            }
        case .document:
            if #available(macOS 11.0, *) {
                return NSWorkspace.shared.icon(for: .plainText)
            } else {
                return NSWorkspace.shared.icon(forFileType: "public.text")
            }
        case .archive:
            if #available(macOS 11.0, *) {
                return NSWorkspace.shared.icon(for: .archive)
            } else {
                return NSWorkspace.shared.icon(forFileType: "public.archive")
            }
        default:
            // Generic document icon
            if #available(macOS 11.0, *) {
                return NSWorkspace.shared.icon(for: .data)
            } else {
                return NSWorkspace.shared.icon(forFileType: "public.data")
            }
        }
    }
    
    private func loadImagePreview(from url: URL) -> NSImage? {
        // Try multiple path variations to find the file
        let possiblePaths = [
            url.path,
            file.fullPath,
            NSHomeDirectory() + "/Desktop/" + file.name,
            NSHomeDirectory() + "/" + file.name
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                if let image = NSImage(contentsOfFile: path) {
                    return createThumbnail(from: image)
        }
            }
        }
        
        return nil
    }
    
    private func createThumbnail(from image: NSImage) -> NSImage? {
        let thumbnailSize = NSSize(width: 60, height: 50)
        
        // Use NSImage's built-in resizing for better quality
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        
        // Calculate aspect fit scaling
        let imageSize = image.size
        let scale = min(thumbnailSize.width / imageSize.width, thumbnailSize.height / imageSize.height)
        let scaledSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = NSPoint(
            x: (thumbnailSize.width - scaledSize.width) / 2,
            y: (thumbnailSize.height - scaledSize.height) / 2
        )
        
        image.draw(in: NSRect(origin: origin, size: scaledSize),
                  from: NSRect(origin: .zero, size: imageSize),
                  operation: .sourceOver,
                  fraction: 1.0)
        
        thumbnail.unlockFocus()
        return thumbnail
    }
    
    private func loadDocumentPreview(from url: URL) -> NSImage? {
        // Check if file exists first
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        // Try to get Quick Look thumbnail
        if #available(macOS 10.15, *) {
            return getQuickLookThumbnail(for: url)
        } else {
            return nil
        }
    }
    
    @available(macOS 10.15, *)
    private func getQuickLookThumbnail(for url: URL) -> NSImage? {
        let size = CGSize(width: 60, height: 50)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail)
        
        var thumbnail: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { (representation, error) in
            if let rep = representation {
                thumbnail = rep.nsImage
            }
            semaphore.signal()
        }
        
        // Wait for thumbnail generation (with timeout)
        _ = semaphore.wait(timeout: .now() + 0.5)
        return thumbnail
    }
    
    private var fileTypeIcon: String {
        switch file.fileType {
        case .image:
            return "photo"
        case .document:
            return "doc.text"
        case .folder:
            return "folder.fill"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .archive:
            return "archivebox"
        case .audio:
            return "music.note"
        case .video:
            return "play.rectangle"
        case .other:
            return "doc"
        }
    }
    
    private var fileTypeColor: Color {
        switch file.fileType {
        case .image:
            return .green
        case .document:
            return .blue
        case .folder:
            return .blue
        case .code:
            return .purple
        case .archive:
            return .brown
        case .audio:
            return .pink
        case .video:
            return .red
        case .other:
            return .gray
        }
    }
}

#Preview {
    let previewChatViewModel = ChatViewModel()
    let sampleMessages = [
        ChatMessage(text: "Hello!", isUser: true, timestamp: Date()),
        ChatMessage(text: "Hi there!", isUser: false, timestamp: Date()),
        ChatMessage(text: "I can run the following command for you. Please review and confirm:", 
                    isUser: false, 
                    timestamp: Date(), 
                    isConfirmationRequest: true, 
                    commandDetails: "ls -la ~/"),
        ChatMessage(text: "Okay, preparing to execute: ls -la ~/", 
                    isUser: false, 
                    timestamp: Date(), 
                    isConfirmationRequest: false, 
                    isActioned: true)
    ]
    previewChatViewModel.messages = sampleMessages
    
    return ContentView().environmentObject(previewChatViewModel)
}
