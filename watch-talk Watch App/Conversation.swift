import Foundation
import AVFoundation
import SwiftUI

// MARK: - Message構造体
/// ユーザーまたはAIのメッセージを表現する構造体
struct Message: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool
}

// MARK: - OpenAI設定とレスポンス定義
struct OpenAI {
    static let apiKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !key.isEmpty else {
            fatalError("OPENAI_API_KEY が Info.plist に設定されていません")
        }
        return key
    }()
}

struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct MessageData: Decodable {
            let role: String
            let content: String
        }
        let message: MessageData
    }
    let choices: [Choice]
}

// MARK: - ConversationManager
/// 会話の状態を管理し、OpenAIへの問い合わせやテキスト読み上げ、会話の記録を行うクラス
final class ConversationManager: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false

    private let speechSynthesizer = AVSpeechSynthesizer()
    
    // 会話記録用ファイルのURL（遅延初期化）
    private lazy var conversationFileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conversation.json")
    }()
    
    init() {
        loadConversation()
    }
    
    /// ユーザーの入力メッセージを追加し、OpenAIに問い合わせる
    func addUserMessage(_ text: String) {
        appendMessage(Message(id: UUID(), text: text, isUser: true))
        sendMessageToOpenAI()
    }
    
    /// AIからの返答メッセージを追加し、テキスト読み上げを実行
    private func addAIMessage(_ text: String) {
        appendMessage(Message(id: UUID(), text: text, isUser: false))
        speak(text: text)
    }
    
    /// 配列にメッセージを追加し、会話内容を保存する
    private func appendMessage(_ message: Message) {
        messages.append(message)
        saveConversation()
    }
    
    /// OpenAI APIへ問い合わせを行い、返答を受け取る
    private func sendMessageToOpenAI() {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            print("Invalid URL")
            return
        }
        
        isLoading = true
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenAI.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 過去のやり取りも含めたリクエスト用メッセージ配列を作成
        let messagesForRequest = messages.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.text
            ]
        }
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messagesForRequest
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("Error creating JSON body: \(error)")
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            defer {
                DispatchQueue.main.async { self?.isLoading = false }
            }
            
            if let error = error {
                print("Request error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                if let reply = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) {
                    DispatchQueue.main.async { self?.addAIMessage(reply) }
                }
            } catch {
                print("Decoding error: \(error)")
                if let responseStr = String(data: data, encoding: .utf8) {
                    print("Response: \(responseStr)")
                }
            }
        }.resume()
    }
    
    /// AVSpeechSynthesizer を使ってテキスト読み上げを実行
    private func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - 会話の保存と読み込み
    
    /// 会話内容をJSONとしてファイルに保存する
    private func saveConversation() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: conversationFileURL, options: [.atomicWrite])
            print("Conversation saved to: \(conversationFileURL)")
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
    
    /// ファイルから会話内容を読み込み、復元する
    private func loadConversation() {
        do {
            let data = try Data(contentsOf: conversationFileURL)
            messages = try JSONDecoder().decode([Message].self, from: data)
            print("Conversation loaded from: \(conversationFileURL)")
        } catch {
            print("No previous conversation found or failed to load: \(error)")
        }
    }
}
