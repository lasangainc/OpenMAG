import SwiftUI
import Foundation

struct FileInfo: Identifiable {
    let id = UUID()
    let name: String
    let fullPath: String
    let fileType: FileType
    let size: String?
    
    enum FileType {
        case image
        case document
        case folder
        case code
        case archive
        case audio
        case video
        case other
        
        static func from(fileName: String) -> FileType {
            let ext = (fileName as NSString).pathExtension.lowercased()
            switch ext {
            case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "heif":
                return .image
            case "pdf", "doc", "docx", "txt", "rtf", "pages":
                return .document
            case "swift", "js", "py", "java", "cpp", "c", "h", "html", "css", "json", "xml":
                return .code
            case "zip", "rar", "7z", "tar", "gz", "dmg":
                return .archive
            case "mp3", "wav", "aac", "flac", "m4a":
                return .audio
            case "mp4", "mov", "avi", "mkv", "wmv", "m4v":
                return .video
            default:
                return fileName.isEmpty ? .folder : .other
            }
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    var text: String // Made var to allow modification
    let isUser: Bool
    let timestamp: Date
    var isConfirmationRequest: Bool = false // New property for confirmation messages
    var commandDetails: String? = nil      // New property to hold the command for confirmation
    var isActioned: Bool = false           // New property to mark if confirmation was actioned
    var files: [FileInfo] = []             // New property for file listings
    var showFileCarousel: Bool = false     // New property to show file carousel
    var commandExplanation: String? = nil  // New property for command explanation
    var isExplanationExpanded: Bool = false // New property to track explanation state
}

struct GroqRequest: Codable {
    let messages: [GroqMessage]
    let model: String
    let temperature: Double
    let max_tokens: Int
}

struct GroqMessage: Codable {
    let role: String
    let content: String
}

struct GroqResponse: Codable {
    let choices: [GroqChoice]
}

struct GroqChoice: Codable {
    let message: GroqMessage
}

// Add CommandLog structure to track executed commands
struct CommandLog: Identifiable, Codable {
    let id = UUID()
    let command: String
    let timestamp: Date
    let output: String?
    let error: String?
    let userPrompt: String
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isLoading: Bool = false
    @Published var showSettings: Bool = false
    @Published var apiKey: String = ""
    
    // Separate conversation history for context (not displayed in UI)
    private var conversationHistory: [ChatMessage] = []
    
    // Command logging
    @Published var commandLogs: [CommandLog] = []
    
    // New state properties for command execution flow
    @Published var pendingCommandToExecute: String? = nil
    @Published var commandOutput: String? = nil
    @Published var commandError: String? = nil
    @Published var originalUserPrompt: String = ""
    
    private let groqEndpoint = "https://api.groq.com/openai/v1/chat/completions"
    private let commandGenerationModel = "llama3-70b-8192"
    private let explanationModel = "llama-3.1-8b-instant"
    
    init() {
        loadAPIKey()
        loadCommandLogs()
        // Initial message if needed, or remove if chat starts blank
        // addAIResponse("Ready to help with your Mac tasks!")
    }
    
    func sendMessage() {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard hasValidAPIKey() else {
            showSettings = true
            return
        }
        
        originalUserPrompt = currentInput
        
        // Store the user message in conversation history (for context, not UI display)
        let userMessage = ChatMessage(
            text: originalUserPrompt,
            isUser: true,
            timestamp: Date()
        )
        conversationHistory.append(userMessage)
        
        currentInput = ""
        isLoading = true
        
        // Use AI to classify the request type
        classifyUserRequest(prompt: originalUserPrompt)
    }
    
    private func classifyUserRequest(prompt: String) {
        // First check if user is asking for command logs
        if isCommandLogRequest(prompt) {
            showCommandLogs()
            return
        }
        
        let systemPrompt = """
        You are a smart request classifier for a macOS automation tool. 
        
        Analyze the user's request and respond with ONLY one word:
        - "COMMAND" if the request is about macOS system operations, file management, system information, or anything that can be accomplished with terminal commands
        - "SEARCH" if the request is a general knowledge question, web search, or information request that would be better answered by Google
        
        Examples:
        - "list my files" → COMMAND
        - "show disk space" → COMMAND  
        - "what processes are running" → COMMAND
        - "find python files" → COMMAND
        - "what is machine learning" → SEARCH
        - "weather in Paris" → SEARCH
        - "latest news about AI" → SEARCH
        - "how to bake a cake" → SEARCH
        
        Consider the context: this is a macOS automation tool, so lean towards COMMAND when in doubt about system-related queries.
        """
        
        let groqMessages = [
            GroqMessage(role: "system", content: systemPrompt),
            GroqMessage(role: "user", content: prompt)
        ]

        callGroqAPI(messages: groqMessages, model: explanationModel, maxTokens: 10) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let classification):
                    let cleanClassification = classification.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    
                    if cleanClassification.contains("SEARCH") {
                        self.searchOnGoogle(query: self.originalUserPrompt)
                    } else {
                        // Default to command generation (including "COMMAND" or any unclear response)
                        self.generateBashCommand(prompt: self.originalUserPrompt)
                    }
                case .failure(let error):
                    // If classification fails, default to command generation
                    print("Classification failed: \(error), defaulting to command generation")
                    self.generateBashCommand(prompt: self.originalUserPrompt)
                }
            }
        }
    }
    
    private func searchOnGoogle(query: String) {
        // URL encode the query
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            addAIResponse("Sorry, I couldn't process that search query.")
            isLoading = false // Ensure loading stops on error
            return
        }
        
        let googleURL = "https://www.google.com/search?q=\(encodedQuery)"
        
        guard let url = URL(string: googleURL) else {
            addAIResponse("Sorry, I couldn't create the search URL.")
            isLoading = false // Ensure loading stops on error
            return
        }
        
        // Open in default browser
        NSWorkspace.shared.open(url)
        
        // Provide feedback to user and stop loading
        addAIResponse("Opened Google search for: \"\(query)\"")
        isLoading = false // Explicitly stop loading after search is initiated
    }
    
    private func generateBashCommand(prompt: String) {
        let systemPrompt = """
        You are an expert macOS system administrator. Given the user's request and conversation context, formulate a single, precise bash command to achieve it.
        Output ONLY the bash command itself, with no explanations, comments, or markdown formatting.
        Ensure the command is safe and common.
        If the request is ambiguous or potentially dangerous, output 'Error: Ambiguous or unsafe request.' instead of a command.
        
        Important: For file listing commands (ls), automatically add the -F flag to show file types (directories get a / suffix).
        For example, use 'ls -F' instead of just 'ls', or 'ls -lF' instead of 'ls -l'.
        
        Consider the conversation context to better understand what the user is trying to accomplish.
        """
        
        // Build conversation context from recent messages (up to 5 messages)
        var groqMessages = [GroqMessage(role: "system", content: systemPrompt)]
        
        // Get the last 5 messages from conversation history (excluding the current one) for context
        let recentMessages = Array(conversationHistory.suffix(5))
        
        for message in recentMessages {
            if message.isUser {
                groqMessages.append(GroqMessage(role: "user", content: message.text))
            } else {
                // For AI messages, provide a summary of what was done
                var aiContent = message.text
                
                // If it was a command execution, mention what was executed
                if let commandDetails = message.commandDetails {
                    aiContent = "I executed the command: \(commandDetails). Result: \(message.text)"
                } else if message.text.contains("Running:") {
                    aiContent = "I \(message.text.lowercased())"
                }
                
                groqMessages.append(GroqMessage(role: "assistant", content: aiContent))
            }
        }
        
        // Add the current user prompt
        groqMessages.append(GroqMessage(role: "user", content: prompt))

        callGroqAPI(messages: groqMessages, model: commandGenerationModel, maxTokens: 150) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let command):
                    if command.starts(with: "Error:") {
                        self.addAIResponse(command) 
                        self.isLoading = false
                    } else {
                        // Automatically enhance ls commands with -F flag if not present
                        let enhancedCommand = self.enhanceLsCommand(command)
                        
                        // Check if command is safe for auto-execution
                        if self.isSafeCommand(enhancedCommand) {
                            // Auto-execute safe commands
                            self.pendingCommandToExecute = enhancedCommand
                            self.addAIResponse("Running: \(enhancedCommand)")
                            self.executeCommand(enhancedCommand)
                        } else {
                            // Require confirmation for risky commands
                            self.pendingCommandToExecute = enhancedCommand
                            let confirmationMessage = ChatMessage(
                                text: "I can run the following command for you. Please review and confirm:",
                                isUser: false,
                                timestamp: Date(),
                                isConfirmationRequest: true,
                                commandDetails: enhancedCommand
                            )
                            
                            // Ensure we clear previous messages before adding confirmation
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                self.messages.removeAll { !$0.isUser }
                                self.messages.append(confirmationMessage)
                            }
                            self.isLoading = false // Allow interaction with confirmation buttons
                        }
                    }
                case .failure(let error):
                    self.handleAPIError("Failed to generate command: \(error.localizedDescription)")
                    self.isLoading = false
                }
            }
        }
    }
    
    private func enhanceLsCommand(_ command: String) -> String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's an ls command that doesn't already have -F
        if trimmedCommand.hasPrefix("ls") && !trimmedCommand.contains("-F") && !trimmedCommand.contains("-f") {
            // Find where the flags end and add F
            let components = trimmedCommand.components(separatedBy: .whitespaces)
            if let lsComponent = components.first, lsComponent == "ls" {
                if components.count > 1 && components[1].hasPrefix("-") {
                    // There are existing flags, add F to them
                    let existingFlags = components[1]
                    let newFlags = existingFlags + "F"
                    return trimmedCommand.replacingOccurrences(of: existingFlags, with: newFlags)
                } else {
                    // No flags, add -F after ls
                    return trimmedCommand.replacingOccurrences(of: "ls", with: "ls -F", options: [.anchored])
                }
            }
        }
        
        return command
    }
    
    private func isSafeCommand(_ command: String) -> Bool {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // List of safe read-only command prefixes
        let safeCommands = [
            "ls", "pwd", "whoami", "date", "uptime", "uname",
            "ps", "top", "df", "du", "free", "cat", "head", 
            "tail", "less", "more", "grep", "find", "locate",
            "which", "where", "file", "stat", "wc", "sort",
            "uniq", "cut", "awk", "sed -n", "echo", "printf",
            "history", "env", "printenv", "id", "groups",
            "finger", "w", "who", "last", "lastlog", "dmesg",
            "mount", "lsof", "netstat", "ifconfig", "ping -c",
            "traceroute", "nslookup", "dig", "host", "curl -s",
            "wget --spider", "ssh -T", "rsync -n", "git status",
            "git log", "git show", "git diff", "git branch",
            "brew list", "brew info", "brew search", "npm list",
            "pip list", "pip show", "python --version", "node --version"
        ]
        
        // Check if command starts with any safe command
        for safeCmd in safeCommands {
            if trimmedCommand.hasPrefix(safeCmd + " ") || trimmedCommand == safeCmd {
                // Additional checks for potentially risky flags
                if trimmedCommand.contains(" -r") && (trimmedCommand.contains("rm") || trimmedCommand.contains("mv")) {
                    return false // rm -r or mv with -r flag
                }
                if trimmedCommand.contains("sudo") {
                    return false // Any sudo command needs confirmation
                }
                if trimmedCommand.contains(" >") || trimmedCommand.contains(" >>") {
                    return false // Output redirection could overwrite files
                }
                return true
            }
        }
        
        // Default to requiring confirmation for unrecognized commands
        return false
    }
    
    // Modified to take messageId to update the specific confirmation message
    func confirmAndExecuteCommand(messageId: UUID) {
        isLoading = true // Show loading for command execution and explanation
        
        if let index = messages.firstIndex(where: { $0.id == messageId && $0.isConfirmationRequest }) {
            // Update the existing message instead of adding a new one
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                messages[index].text = "Okay, preparing to execute: \(messages[index].commandDetails ?? "")"
                messages[index].isConfirmationRequest = false // No longer a confirmation request
                messages[index].isActioned = true
                messages[index].commandDetails = nil // Clear command details after actioning
            }
        }
        
        // Execute the command immediately
        guard let command = pendingCommandToExecute else {
            isLoading = false
            addAIResponse("Error: No command was pending for execution.")
            return
        }
        
        executeCommand(command)
    }
    
    private func executeCommand(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = ["-c", command]

            let workingDirectoryPath = self.extractDirectoryFromCommand(command)
            if FileManager.default.fileExists(atPath: workingDirectoryPath) {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath)
            } else {
                process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
            }
            
            print("🚀 Executing command: '\(command)' in directory: \(process.currentDirectoryURL?.path ?? "UNKNOWN")")

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Setup termination handler to process output asynchronously
            process.terminationHandler = { [weak self] terminatedProcess in
                guard let self = self else { return }
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("📤 Command output: \(output ?? "None")")
                print("🚨 Command error: \(error ?? "None")")

                DispatchQueue.main.async {
                    self.processCommandResult(
                        output: output?.isEmpty == false ? output : nil,
                        error: error?.isEmpty == false ? error : nil
                    )
                }
            }

            do {
                try process.run() // This is now non-blocking
            } catch {
                DispatchQueue.main.async {
                    self.processCommandResult(
                        output: nil,
                        error: "Failed to launch command: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    func processCommandResult(output: String?, error: String?) {
        self.commandOutput = output
        self.commandError = error
        
        guard let executedCommand = self.pendingCommandToExecute else {
            self.isLoading = false
            self.addAIResponse("Error: No command was pending for execution.")
            return
        }

        // Save command to log
        saveCommandLog(command: executedCommand, output: output, error: error)
        
        explainCommandOutputAndError(command: executedCommand, output: output, error: error)
        self.pendingCommandToExecute = nil // Clear after execution and explanation starts
    }

    private func explainCommandOutputAndError(command: String, output: String?, error: String?) {
        let systemPrompt = """
        The user originally asked: '\(originalUserPrompt)'.
        The command '\(command)' was executed.
        Standard output: '\(output ?? "None")'.
        Standard error: '\(error ?? "None")'.
        Concisely explain the outcome to the user. If there was an error, explain it clearly, or else, DO NOT MENTION WEATHER OR NOT THERE WAS AN ERROR. 
        Keep it short and user-friendly. DO NOT include the command in the explanation.
        """
        let groqMessages = [
            GroqMessage(role: "system", content: systemPrompt)
        ]

        callGroqAPI(messages: groqMessages, model: explanationModel, maxTokens: 200) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false // Finished the whole process
                switch result {
                case .success(let explanation):
                    // Check if this is a file listing command and parse files
                    let (shouldShowCarousel, parsedFiles) = self.parseFilesFromOutput(command: command, output: output)
                    
                    let aiMessage = ChatMessage(
                        text: explanation,
                        isUser: false,
                        timestamp: Date(),
                        files: parsedFiles,
                        showFileCarousel: shouldShowCarousel
                    )
                    
                    // Store in conversation history for context
                    self.conversationHistory.append(aiMessage)
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        // Remove all previous AI messages (non-user messages)
                        self.messages.removeAll { !$0.isUser }
                        // Add the new AI message with file info
                        self.messages.append(aiMessage)
                    }
                case .failure(let apiError):
                    self.handleAPIError("Failed to get explanation: \(apiError.localizedDescription)")
                }
                self.originalUserPrompt = "" 
                self.commandOutput = nil
                self.commandError = nil
            }
        }
    }
    
    private func parseFilesFromOutput(command: String, output: String?) -> (shouldShowCarousel: Bool, files: [FileInfo]) {
        guard let output = output, !output.isEmpty else {
            return (false, [])
        }
        
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Check if this is a file listing command
        let isListingCommand = trimmedCommand.hasPrefix("ls") || 
                              trimmedCommand.hasPrefix("find") ||
                              trimmedCommand.contains("*.") // Commands with wildcards
        
        guard isListingCommand else {
            return (false, [])
        }
        
        // Parse the output to extract file names
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var files: [FileInfo] = []
        let baseDirectory = extractDirectoryFromCommand(command)
        
        for line in lines {
            // Handle different ls output formats
            var fileName: String
            var isDirectory = false
            
            if trimmedCommand.contains("-l") {
                // Long format: parse the last column as filename
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 9 {
                    fileName = components[8...].joined(separator: " ")
                    isDirectory = line.hasPrefix("d")
                } else {
                    continue
                }
            } else {
                // Simple format: entire line is filename
                fileName = line
                
                // Check for -F flag indicators (much more reliable)
                if fileName.hasSuffix("/") {
                    // Directory indicator from ls -F
                    isDirectory = true
                    fileName = String(fileName.dropLast()) // Remove the / suffix
                } else if fileName.hasSuffix("*") {
                    // Executable file from ls -F
                    fileName = String(fileName.dropLast()) // Remove the * suffix
                } else if fileName.hasSuffix("@") {
                    // Symbolic link from ls -F  
                    fileName = String(fileName.dropLast()) // Remove the @ suffix
                } else {
                    // Regular file or fallback detection
                    
                    // Build full path to check if it's actually a directory (fallback)
                    let testPath: String
                    if baseDirectory.isEmpty {
                        testPath = NSHomeDirectory() + "/" + fileName
                    } else {
                        testPath = baseDirectory + "/" + fileName
                    }
                    let cleanTestPath = (testPath as NSString).standardizingPath
                    
                    // Check if it's actually a directory
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: cleanTestPath, isDirectory: &isDir) {
                        isDirectory = isDir.boolValue
                    } else {
                        // Fallback: guess based on filename patterns (last resort)
                        isDirectory = !fileName.contains(".") && (
                            fileName.lowercased().contains("folder") ||
                            fileName.lowercased().contains("documents") ||
                            fileName.lowercased().contains("downloads") ||
                            fileName.lowercased().contains("applications") ||
                            fileName.lowercased().contains("desktop") ||
                            fileName.lowercased().contains("pictures") ||
                            fileName.lowercased().contains("movies") ||
                            fileName.lowercased().contains("music") ||
                            fileName == "Applications" ||
                            fileName == "Documents" ||
                            fileName == "Downloads" ||
                            fileName == "Desktop" ||
                            fileName == "Pictures" ||
                            fileName == "Library" ||
                            fileName == "Public"
                        )
                    }
                }
            }
            
            // Skip hidden files unless explicitly requested
            if fileName.hasPrefix(".") && !trimmedCommand.contains("-a") {
                continue
            }
            
            // Build proper full path
            var fullPath: String
            if baseDirectory.isEmpty {
                // No directory specified, use user's home directory
                fullPath = NSHomeDirectory() + "/" + fileName
            } else {
                fullPath = baseDirectory + "/" + fileName
            }
            
            // Clean up the path (remove double slashes, etc.)
            fullPath = (fullPath as NSString).standardizingPath
            
            let fileType = isDirectory ? FileInfo.FileType.folder : FileInfo.FileType.from(fileName: fileName)
            
            // Extract just the filename for display (not the full path)
            let displayName = (fileName as NSString).lastPathComponent
            
            let fileInfo = FileInfo(
                name: displayName,
                fullPath: fullPath,
                fileType: fileType,
                size: nil // Could be enhanced to parse size from ls -l
            )
            
            files.append(fileInfo)
        }
        
        // Show carousel if we have files and it's reasonable to display them
        let shouldShowCarousel = files.count > 0 && files.count <= 50 // Don't show for huge listings
        
        return (shouldShowCarousel, files)
    }
    
    private func extractDirectoryFromCommand(_ command: String) -> String {
        // Extract directory path from commands like "ls ~/Desktop" or "ls /Users/benji"
        let components = command.components(separatedBy: .whitespaces)
        
        for component in components.dropFirst() { // Skip the command itself
            if !component.hasPrefix("-") && !component.isEmpty { // Skip flags
                if component.hasPrefix("~/") {
                    return component.replacingOccurrences(of: "~/", with: NSHomeDirectory())
                } else if component.hasPrefix("/") {
                    return component
                } else {
                    // Relative path - resolve to absolute from user's home directory
                    return NSHomeDirectory() + "/" + component
                }
            }
        }
        
        return NSHomeDirectory() // Default to user's home directory
    }

    // Modified to take messageId to update the specific confirmation message
    func rejectCommand(messageId: UUID) {
        isLoading = false // No further processing needed
        if let index = messages.firstIndex(where: { $0.id == messageId && $0.isConfirmationRequest }) {
            let rejectedCommand = messages[index].commandDetails ?? "a command"
            
            // Update the existing message instead of adding a new one
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                messages[index].text = "Command cancelled: \(rejectedCommand)"
                messages[index].isConfirmationRequest = false // No longer a confirmation request
                messages[index].isActioned = true
                messages[index].commandDetails = nil // Clear command details after actioning
            }
        } else {
             // Fallback if the message wasn't found - use the standard method to ensure proper clearing
            addAIResponse("Command cancellation processed.")
        }
        pendingCommandToExecute = nil 
        originalUserPrompt = ""
    }

    private func callGroqAPI(messages: [GroqMessage], model: String, maxTokens: Int, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: groqEndpoint) else {
            completion(.failure(NSError(domain: "ChatViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let groqRequest = GroqRequest(
            messages: messages,
            model: model,
            temperature: 0.7, 
            max_tokens: maxTokens
        )

        do {
            request.httpBody = try JSONEncoder().encode(groqRequest)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "ChatViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }

            do {
                let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
                if let firstChoice = groqResponse.choices.first {
                    completion(.success(firstChoice.message.content))
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                     let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                     completion(.failure(NSError(domain: "ChatViewModel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(responseBody)"])))
                }
                else {
                    completion(.failure(NSError(domain: "ChatViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "No choices in response or malformed data"])))
                }
            } catch {
                let responseBody = String(data: data, encoding: .utf8) ?? "Failed to decode response body"
                completion(.failure(NSError(domain: "ChatViewModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response: \(error.localizedDescription). Body: \(responseBody)"])))

            }
        }.resume()
    }
    
    private func addAIResponse(_ responseText: String) {
        let aiMessage = ChatMessage(
            text: responseText,
            isUser: false,
            timestamp: Date()
        )
        
        // Store in conversation history for context
        conversationHistory.append(aiMessage)
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            // Remove all previous AI messages (non-user messages)
            messages.removeAll { !$0.isUser }
            // Add the new AI message to UI
            messages.append(aiMessage)
        }
    }

    private func handleAPIError(_ errorMessageText: String) {
        // More specific error handling can be added here if needed
        let errorResponse = "Sorry, an error occurred. Details: \(errorMessageText)"
        addAIResponse(errorResponse)
        isLoading = false
    }

    func saveAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: "GroqAPIKey")
    }

    private func loadAPIKey() {
        apiKey = UserDefaults.standard.string(forKey: "GroqAPIKey") ?? ""
    }

    func hasValidAPIKey() -> Bool {
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Command Explanation Functions
    
    func explainCommand(messageId: UUID) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageId }),
              let command = messages[messageIndex].commandDetails else {
            return
        }
        
        // If explanation already exists, just toggle visibility
        if messages[messageIndex].commandExplanation != nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                messages[messageIndex].isExplanationExpanded.toggle()
            }
            return
        }
        
        // Generate explanation using AI
        let systemPrompt = """
        Explain what the following command does in 1-2 simple sentences. Be concise and user-friendly.
        Focus on what the command accomplishes, not technical details, but do say if the command is risky or not.
        Command: \(command)
        """
        
        let groqMessages = [
            GroqMessage(role: "system", content: systemPrompt)
        ]
        
        callGroqAPI(messages: groqMessages, model: explanationModel, maxTokens: 100) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let explanation):
                    if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            self.messages[index].commandExplanation = explanation
                            self.messages[index].isExplanationExpanded = true
                        }
                    }
                case .failure(_):
                    // Fallback explanation if AI fails
                    if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            self.messages[index].commandExplanation = "This command will perform a system operation on your Mac."
                            self.messages[index].isExplanationExpanded = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Command Logging Functions
    
    private func isCommandLogRequest(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        let logKeywords = [
            "show command log", "command log", "command history", "show commands",
            "recent commands", "commands run", "executed commands", "command list",
            "log of commands", "what commands", "commands from", "show log"
        ]
        
        return logKeywords.contains { lowercased.contains($0) }
    }
    
    private func showCommandLogs() {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentCommands = commandLogs.filter { $0.timestamp >= oneWeekAgo }
        
        isLoading = false // No need to show loading for instant response
        
        if recentCommands.isEmpty {
            addAIResponse("No commands have been executed in the last week.")
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd"
            
            var logText = "Commands executed in the last week:\n\n"
            
            for log in recentCommands.reversed() { // Most recent first
                logText += "\(log.command) - \(dateFormatter.string(from: log.timestamp))\n"
            }
            
            addAIResponse(logText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    private func saveCommandLog(command: String, output: String?, error: String?) {
        let commandLog = CommandLog(
            command: command,
            timestamp: Date(),
            output: output,
            error: error,
            userPrompt: originalUserPrompt
        )
        
        commandLogs.append(commandLog)
        
        // Keep only the last 100 commands to prevent excessive storage
        if commandLogs.count > 100 {
            commandLogs.removeFirst(commandLogs.count - 100)
        }
        
        saveCommandLogsToStorage()
    }
    
    private func saveCommandLogsToStorage() {
        do {
            let data = try JSONEncoder().encode(commandLogs)
            UserDefaults.standard.set(data, forKey: "CommandLogs")
        } catch {
            print("Failed to save command logs: \(error)")
        }
    }
    
    private func loadCommandLogs() {
        guard let data = UserDefaults.standard.data(forKey: "CommandLogs") else {
            return
        }
        
        do {
            commandLogs = try JSONDecoder().decode([CommandLog].self, from: data)
        } catch {
            print("Failed to load command logs: \(error)")
            commandLogs = []
        }
    }
} 