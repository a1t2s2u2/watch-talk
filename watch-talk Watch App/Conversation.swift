import Foundation
import AVFoundation
import SwiftUI

struct OpenAI {
    // Info.plist から Secrets.xcconfig に記載されたキーを取得
    static let apiKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !key.isEmpty else {
            fatalError("OPENAI_API_KEY が Info.plist に設定されていません")
        }
        return key
    }()
}


final class ConversationManager: ObservableObject {
    @Published var messages: [[String: String]] = []
    @Published var isLoading = false

    private let synthesizer = AVSpeechSynthesizer()
    
    // 会話記録用ファイルのパス
    private let conversationFileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watch-talk-record.json")
    }()

    init() {
        loadConversation()
    }
    
    // ユーザーのメッセージを追加し、OpenAIに問い合わせる
    func addUserMessage(_ text: String) {
        append(["role": "user", "text": text])
        sendToOpenAI()
    }
    
    // メッセージを配列に追加して保存
    private func append(_ message: [String: String]) {
        messages.append(message)
        saveConversation()
    }
    
    // OpenAIに問い合わせ、返答を取得する
    private func sendToOpenAI() {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
        isLoading = true
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(OpenAI.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // API の仕様に合わせ、各メッセージは "role" と "content" として送信
        let requestMessages = messages.map { message in [
            "role": message["role"] ?? "",
            "content": message["text"] ?? ""
        ]}
        
        request.httpBody = try! JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "messages": requestMessages
        ])
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            defer {
                DispatchQueue.main.async { self?.isLoading = false }
            }
            
            guard error == nil, let data = data else {
                print("通信エラー または データがありません")
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("JSONのパースに失敗しました")
                    return
                }
                
                guard let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let messageData = firstChoice["message"] as? [String: Any],
                      let content = messageData["content"] as? String else {
                    print("レスポンスの形式が不正です")
                    return
                }
                
                let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                
                DispatchQueue.main.async {
                    self?.append(["role": "assistant", "text": trimmedContent])
                    self?.speak(trimmedContent)
                }
            } catch {
                print("JSONパースエラー: \(error)")
            }
        }.resume()
    }
    
    // テキスト読み上げ
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
    }
    
    // 会話をJSON形式で保存する
    private func saveConversation() {
        do {
            // 最新の4件だけ残す（新しい方が配列の末尾にあると仮定）
            if messages.count > 4 {
                messages = Array(messages.suffix(4))
            }
            let data = try JSONEncoder().encode(messages)
            try data.write(to: conversationFileURL, options: .atomic)
        } catch {
            print("会話の保存に失敗: \(error)")
        }
    }
    
    // JSONファイルから会話を読み込む
    private func loadConversation() {
        do {
            let data = try Data(contentsOf: conversationFileURL)
            messages = try JSONDecoder().decode([[String: String]].self, from: data)
        } catch {
            print("会話の読み込みに失敗またはファイルが存在しません: \(error)")
        }
    }
    
    // 会話履歴を削除するメソッド
    func clearHistory() {
        messages.removeAll()
        do {
            if FileManager.default.fileExists(atPath: conversationFileURL.path) {
                try FileManager.default.removeItem(at: conversationFileURL)
            }
        } catch {
            print("会話ファイルの削除に失敗: \(error)")
        }
    }
}
