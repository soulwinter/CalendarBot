import Foundation

struct DifyEvent: Codable {
    let dtstart: String
    let dtend: String
    let summary: String
    let location: String?
    let description: String?
}

struct DifyResponse: Codable {
    let status: Int
    let message: String?
    let events: [DifyEvent]?
}

struct DifyAPIResponse: Codable {
    let event: String
    let task_id: String
    let id: String
    let message_id: String
    let mode: String
    let answer: String
    let created_at: Int
    
    struct Metadata: Codable {
        let usage: Usage
        
        struct Usage: Codable {
            let prompt_tokens: Int
            let completion_tokens: Int
            let total_tokens: Int
            let total_price: String
            let currency: String
            let latency: Double
        }
    }
    
    let metadata: Metadata
}

class DifyAPI {
    static let shared = DifyAPI()
    private let baseURL = "https://api.dify.ai/v1/completion-messages"
    private let apiKey = Config.difyAPIKey
    
    func submitEvents(existedEvents: String, plans: String) async throws -> DifyResponse {
        print("开始准备 Dify API 请求...")
        
        guard let url = URL(string: baseURL) else {
            print("❌ URL 创建失败: \(baseURL)")
            throw URLError(.badURL)
        }
        print("✅ URL 创建成功: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "inputs": [
                "existed_events": existedEvents,
                "plans": plans
            ],
            "response_mode": "blocking",
            "user": "abc-123"
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData
            print("✅ 请求体准备成功:")
            print("Headers: \(request.allHTTPHeaderFields ?? [:])")
            if let bodyString = String(data: jsonData, encoding: .utf8) {
                print("Body: \(bodyString)")
            }
        } catch {
            print("❌ 请求体序列化失败: \(error)")
            throw error
        }
        
        print("开始发送请求...")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("收到响应: HTTP \(httpResponse.statusCode)")
                print("Response Headers: \(httpResponse.allHeaderFields)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response Body: \(responseString)")
            }
            
            do {
                // 首先解析外层响应
                let apiResponse = try JSONDecoder().decode(DifyAPIResponse.self, from: data)
                print("✅ API响应解析成功")
                
                // 然后解析 answer 字段中的实际响应
                if let answerData = apiResponse.answer.data(using: .utf8) {
                    let actualResponse = try JSONDecoder().decode(DifyResponse.self, from: answerData)
                    print("✅ 响应内容解析成功: status=\(actualResponse.status)")
                    return actualResponse
                } else {
                    throw NSError(domain: "DifyAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析answer字段"])
                }
            } catch {
                print("❌ 响应解析失败: \(error)")
                throw error
            }
        } catch {
            print("❌ 网络请求失败: \(error)")
            throw error
        }
    }
}

extension ISO8601DateFormatter {
    static let difyFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
} 