import Foundation

// Real MCP (Model Context Protocol, JSON-RPC 2.0 over HTTP) client: initialize handshake,
// tools/list, tools/call. These three methods are part of the MCP spec itself — any
// compliant server must answer them — so this is genuine protocol support, not a guess.
//
// What IS a guess: which tool name/args the user's actual cTrader MCP server uses for
// candle history. The project spec's own Appendix A names are proposals pending
// confirmation (spec §20, open question #1) — nobody has seen this server's real tool
// list. So fetchCandleHistory() tries the Appendix A name and a couple of obvious
// synonyms, parses whatever comes back as leniently as real-world field-naming requires,
// and reports exactly which attempt (if any) worked — it never claims live data arrived
// if parsing didn't actually produce usable bars.
struct MCPConnectionError: Error { let message: String }

enum MCPClient {
    private static func rpcRequest(config: MCPConfig, method: String, params: [String: Any]) async -> Result<[String: Any], MCPConnectionError> {
        guard let url = config.url else { return .failure(MCPConnectionError(message: "Invalid host/port/path")) }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.authToken.isEmpty {
            request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(MCPConnectionError(message: "No HTTP response"))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(MCPConnectionError(message: "Server returned HTTP \(http.statusCode)"))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(MCPConnectionError(message: "Response wasn't a JSON object"))
            }
            if let rpcError = json["error"] as? [String: Any] {
                let msg = rpcError["message"] as? String ?? "unknown RPC error"
                return .failure(MCPConnectionError(message: msg))
            }
            guard let result = json["result"] as? [String: Any] else {
                return .failure(MCPConnectionError(message: "No 'result' in RPC response"))
            }
            return .success(result)
        } catch {
            return .failure(MCPConnectionError(message: error.localizedDescription))
        }
    }

    static func testConnection(config: MCPConfig) async -> Result<Void, MCPConnectionError> {
        let result = await rpcRequest(config: config, method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "clientInfo": ["name": "SetupRushTrader", "version": "0.3"],
        ])
        return result.map { _ in () }
    }

    static func listTools(config: MCPConfig) async -> Result<[String], MCPConnectionError> {
        let result = await rpcRequest(config: config, method: "tools/list", params: [:])
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let value):
            guard let tools = value["tools"] as? [[String: Any]] else {
                return .failure(MCPConnectionError(message: "No 'tools' array in tools/list response"))
            }
            return .success(tools.compactMap { $0["name"] as? String })
        }
    }

    // MCP tool-call results wrap their payload as result.content[0].text (per the MCP
    // spec's tool-result shape) — the actual bar data is a second layer of JSON inside that.
    static func callTool(config: MCPConfig, name: String, arguments: [String: Any]) async -> Result<Any, MCPConnectionError> {
        let result = await rpcRequest(config: config, method: "tools/call", params: ["name": name, "arguments": arguments])
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let value):
            if let isError = value["isError"] as? Bool, isError {
                return .failure(MCPConnectionError(message: "Tool '\(name)' returned an error"))
            }
            guard let content = value["content"] as? [[String: Any]], let text = content.first?["text"] as? String else {
                return .failure(MCPConnectionError(message: "Tool '\(name)' returned no text content"))
            }
            guard let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else {
                return .failure(MCPConnectionError(message: "Tool '\(name)' content wasn't valid JSON"))
            }
            return .success(payload)
        }
    }

    // Tries the spec's Appendix A name first (get_trendbars), then two common synonyms a
    // real server might use instead — one attempt each, first match wins. Field names
    // within each bar are matched leniently (o/open, h/high, etc.) since the real schema
    // is unconfirmed.
    static func fetchCandleHistory(config: MCPConfig, symbol: String, timeframe: String, bars: Int) async -> Result<[Candle], MCPConnectionError> {
        let toolsResult = await listTools(config: config)
        guard case .success(let tools) = toolsResult else {
            if case .failure(let error) = toolsResult { return .failure(error) }
            return .failure(MCPConnectionError(message: "Could not list tools"))
        }

        let candidates = ["get_trendbars", "get_candles", "get_history"]
        guard let toolName = candidates.first(where: { name in tools.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }) else {
            return .failure(MCPConnectionError(message: "No candle-history tool found among \(tools.count) available (tried \(candidates.joined(separator: ", ")))"))
        }

        let callResult = await callTool(config: config, name: toolName, arguments: [
            "symbol": symbol, "timeframe": timeframe, "count": bars,
        ])
        guard case .success(let payload) = callResult else {
            if case .failure(let error) = callResult { return .failure(error) }
            return .failure(MCPConnectionError(message: "Tool call failed"))
        }

        guard let rawBars = payload as? [[String: Any]], !rawBars.isEmpty else {
            return .failure(MCPConnectionError(message: "'\(toolName)' response wasn't a non-empty array of bars"))
        }

        let candles: [Candle] = rawBars.compactMap { bar in
            guard let o = decimal(bar, "o", "open"), let h = decimal(bar, "h", "high"),
                  let l = decimal(bar, "l", "low"), let c = decimal(bar, "c", "close") else { return nil }
            let volume = Int(truncating: (decimal(bar, "v", "volume") ?? 0) as NSNumber)
            let time = date(bar, "t", "time", "timestamp") ?? Date()
            return Candle(time: time, o: o, h: h, l: l, c: c, volume: volume, isClosed: true)
        }
        guard candles.count == rawBars.count, !candles.isEmpty else {
            return .failure(MCPConnectionError(message: "'\(toolName)' bars were missing expected OHLC fields"))
        }
        return .success(candles)
    }

    private static func decimal(_ bar: [String: Any], _ keys: String...) -> Decimal? {
        for key in keys {
            if let n = bar[key] as? NSNumber { return Decimal(string: n.stringValue) }
            if let s = bar[key] as? String, let d = Decimal(string: s) { return d }
        }
        return nil
    }

    private static func date(_ bar: [String: Any], _ keys: String...) -> Date? {
        for key in keys {
            if let n = bar[key] as? NSNumber {
                let v = n.doubleValue
                return Date(timeIntervalSince1970: v > 1_000_000_000_000 ? v / 1000 : v) // ms vs s epoch
            }
            if let s = bar[key] as? String {
                if let d = ISO8601DateFormatter().date(from: s) { return d }
            }
        }
        return nil
    }
}
