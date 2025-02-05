import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(conversationManager.messages) { message in
                    HStack {
                        if message.isUser {
                            Spacer()
                            Text(message.text)
                                .padding(8)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        } else {
                            Text(message.text)
                                .padding(8)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(8)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
            if conversationManager.isLoading {
                ProgressView()
                    .padding()
            }
            Button(action: {
                presentTextInput()
            }) {
                Text("入力")
            }
            .padding()
        }
    }
    
    // Apple Watchのテキスト入力を呼び出す
    func presentTextInput() {
        WKExtension.shared().visibleInterfaceController?.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            if let results = results,
               let text = results.first as? String,
               !text.isEmpty {
                DispatchQueue.main.async {
                    conversationManager.addUserMessage(text)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
