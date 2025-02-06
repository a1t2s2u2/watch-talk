import SwiftUI
import WatchKit

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct OffsetAwareScrollView<Content: View>: View {
    let content: Content
    @Binding var offset: CGPoint

    init(offset: Binding<CGPoint>, @ViewBuilder content: () -> Content) {
        self._offset = offset
        self.content = content()
    }

    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .global).origin)
            }
            .frame(height: 0)
            content
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            offset = value
        }
    }
}

struct ChatTheme: Identifiable {
    let id = UUID()
    let name: String
    let chatBackground: Color
    let userBubbleColor: Color
    let userTextColor: Color
    let assistantBubbleColor: Color
    let assistantTextColor: Color
}

let chatThemes: [String: ChatTheme] = [
    "Light": ChatTheme(name: "Light",
                         chatBackground: .white,
                         userBubbleColor: Color.blue.opacity(0.2),
                         userTextColor: .black,
                         assistantBubbleColor: Color.green.opacity(0.2),
                         assistantTextColor: .black),
    "Dark": ChatTheme(name: "Dark",
                        // 完全な黒ではなく、やや明るめの暗いグレーに変更
                        chatBackground: Color(white: 0.1),
                        userBubbleColor: Color.blue.opacity(0.4),
                        userTextColor: .white,
                        assistantBubbleColor: Color.green.opacity(0.4),
                        assistantTextColor: .white),
    "Blue": ChatTheme(name: "Blue",
                      chatBackground: Color.blue.opacity(0.1),
                      userBubbleColor: Color.blue.opacity(0.3),
                      userTextColor: .white,
                      assistantBubbleColor: Color.gray.opacity(0.3),
                      assistantTextColor: .white)
]

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var selectedThemeKey: String = "Light"
    
    var body: some View {
        TabView {
            ChatView(conversationManager: conversationManager,
                     chatTheme: chatThemes[selectedThemeKey] ?? chatThemes["Light"]!)
            SettingsView(conversationManager: conversationManager,
                         selectedThemeKey: $selectedThemeKey)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
}

struct ChatView: View {
    @ObservedObject var conversationManager: ConversationManager
    var chatTheme: ChatTheme
    @State private var scrollOffset: CGPoint = .zero

    var body: some View {
        ZStack {
            chatTheme.chatBackground.ignoresSafeArea()
            
            // 履歴がない場合はプレースホルダーを表示
            if conversationManager.messages.isEmpty {
                Text("タップで会話")
                    .foregroundColor(chatTheme.assistantTextColor)
                    .font(.headline)
            } else {
                VStack(spacing: 0) {
                    OffsetAwareScrollView(offset: $scrollOffset) {
                        ForEach(Array(conversationManager.messages.enumerated()), id: \.offset) { _, message in
                            HStack {
                                if message["role"] == "user" {
                                    Spacer()
                                    Text(message["text"] ?? "")
                                        .foregroundColor(chatTheme.userTextColor)
                                        .padding(8)
                                        .background(chatTheme.userBubbleColor)
                                        .cornerRadius(8)
                                } else {
                                    Text(message["text"] ?? "")
                                        .foregroundColor(chatTheme.assistantTextColor)
                                        .padding(8)
                                        .background(chatTheme.assistantBubbleColor)
                                        .cornerRadius(8)
                                    Spacer()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            
            if conversationManager.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.7)
            }
        }
        .onTapGesture { presentTextInput() }
    }
    
    func presentTextInput() {
        WKExtension.shared().visibleInterfaceController?
            .presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
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

struct SettingsView: View {
    @ObservedObject var conversationManager: ConversationManager
    @Binding var selectedThemeKey: String
    
    var themeKeys: [String] {
        Array(chatThemes.keys).sorted()
    }
    
    @State private var showDeletionConfirmation = false
    @State private var showDeletionMessage = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("テーマ", selection: $selectedThemeKey) {
                ForEach(themeKeys, id: \.self) { key in
                    Text(key)
                        .foregroundColor(.white)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(height: 80)
            
            // 会話記録がない場合はタップ操作を無効化したテキストを表示
            if conversationManager.messages.isEmpty {
                Text("会話記録はありません")
                    .foregroundColor(.white)
                    .padding()
                    .allowsHitTesting(false)
            } else {
                // 会話が追加された場合は削除完了メッセージを非表示にする
                if showDeletionMessage {
                    Text("会話履歴と表示が消えました")
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: {
                    showDeletionConfirmation = true
                }) {
                    Text("データ削除")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(conversationManager.messages.isEmpty)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .navigationTitle("設定")
        .background(Color.black.ignoresSafeArea())
        .alert(isPresented: $showDeletionConfirmation) {
            Alert(
                title: Text("確認"),
                message: Text("本当にデータを削除しますか？"),
                primaryButton: .destructive(Text("削除"), action: {
                    conversationManager.clearHistory()
                    showDeletionMessage = true
                }),
                secondaryButton: .cancel()
            )
        }
        .onChange(of: conversationManager.messages) { oldMessages, newMessages in
            // 会話が追加されたら削除完了メッセージを非表示にする
            if !newMessages.isEmpty {
                showDeletionMessage = false
            }
        }
    }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
