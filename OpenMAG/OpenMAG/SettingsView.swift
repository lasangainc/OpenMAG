import SwiftUI

struct SettingsView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var tempAPIKey: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
            
            // API Key Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    
                    Text("Groq API Key")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                // API Key Input
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .frame(height: 38)
                    
                    HStack {
                        SecureField("Enter your Groq API key", text: $tempAPIKey)
                            .font(.system(size: 14))
                            .textFieldStyle(.plain)
                        
                        if !tempAPIKey.isEmpty {
                            Button(action: {
                                tempAPIKey = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                
                // Info Text
                Text("Get your free API key from console.groq.com")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Save Button
            Button(action: {
                chatViewModel.apiKey = tempAPIKey
                chatViewModel.saveAPIKey()
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Save API Key")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tempAPIKey.isEmpty ? Color.gray : Color.blue)
                )
            }
            .buttonStyle(.plain)
            .disabled(tempAPIKey.isEmpty)
            .animation(.easeInOut(duration: 0.2), value: tempAPIKey.isEmpty)
            
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 340, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .onAppear {
            tempAPIKey = chatViewModel.apiKey
        }
    }
}

#Preview {
    SettingsView(
        chatViewModel: ChatViewModel(),
        isPresented: .constant(true)
    )
} 