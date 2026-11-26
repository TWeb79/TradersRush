import Foundation

// Spec: SETUPRUSH_TRADER_PROJECT_SPEC.md §6.4. Prices use Decimal (never Double) per spec's
// explicit requirement — avoids float drift once real tick/currency math lands.

enum TradeSide { case buy, sell, unknown }

struct Trade {
    var price: Decimal
    var qty: Int
    var side: TradeSide
    var time: Date
}

struct Candle: Identifiable {
    var id: Date { time }
    var time: Date
    var o, h, l, c: Decimal
    var volume: Int
    var isClosed: Bool
}

struct PriceBin {
    var price: Decimal
    var bidVolume: Int
    var askVolume: Int
    var delta: Int { askVolume - bidVolume }
}

struct FootprintBar: Identifiable {
    var id: Date { time }
    var time: Date
    var priceBins: [PriceBin]
    var totalVolume: Int { priceBins.reduce(0) { $0 + $1.bidVolume + $1.askVolume } }
}

// CH-34: footprint can show either raw bid/ask volume per bin or just the net delta —
// real footprint tools (and the DeltaTrader playbook §11) treat these as distinct reads.
enum FootprintDisplayMode: String, CaseIterable, Identifiable {
    case bidAsk = "Bid × Ask"
    case delta = "Delta"
    var id: String { rawValue }
}

// Spec §6.4, trimmed. Positions/orders are never synthesized by MockTradingGateway — an
// invented open position would misrepresent real account risk, unlike a mock price series.
// They stay genuinely empty until a real gateway/account connects (CX brief §16).
struct Position: Identifiable {
    let id = UUID()
    var instrument: String
    var side: TradeSide
    var volume: Int
    var avgPrice: Decimal
    // Bracket, resolved to absolute prices at entry from the ticket's SL/TP/TSL/BE
    // distances. nil = that leg wasn't enabled. slPrice is mutated in place by the
    // simulated engine as BE/TSL ratchet it (see ContentView.checkPositions).
    var slPrice: Decimal?
    var tpPrice: Decimal?
    var trailDistance: Decimal?
    var beTrigger: Decimal?
    var beArmed = false
}

struct WorkingOrder: Identifiable {
    let id = UUID()
    var instrument: String
    var side: TradeSide
    var type: String
    var volume: Int
    var price: Decimal
}

// Ticket's bracket inputs, in price-distance units (not yet ticks/R-multiple — spec TR-20
// scope). Resolved to absolute prices on submit (see ContentView.submit).
struct BracketSettings: Equatable {
    var slEnabled = true
    var slDistance: Decimal = 2.0
    var tpEnabled = true
    var tpDistance: Decimal = 4.0
    var tslEnabled = false
    var tslDistance: Decimal = 1.5
    var beEnabled = false
    var beTrigger: Decimal = 1.0
}

struct LadderLevel: Identifiable {
    var price: Decimal
    var id: Decimal { price }
    var bidSize: Int
    var askSize: Int
}

// Spec §6.3 TradingGateway, trimmed to what the prototype's chart/footprint/ladder view
// needs. Real connect()/orders/etc. land once the remote MCP endpoint (host/port TBD) is provided.
protocol TradingGateway {
    func history(tickSize: Decimal, bars: Int) -> [Candle]
    func footprint(for candles: [Candle], tickSize: Decimal) -> [FootprintBar]
    func ladder(around last: Decimal, tickSize: Decimal, levels: Int) -> [LadderLevel]
}

// Spec §2.2/§2.2a: host/port/path MUST be user-entered at runtime, nothing hardcoded.
// Defaults here follow this repo's own RULES_ports.md convention (project 62, FastAPI/
// service category) as a reasonable starting point to prefill — not a claim that a real
// server is listening there.
struct MCPConfig: Equatable {
    var host: String = "localhost"
    var port: String = "8162"
    var path: String = "/mcp"
    var useTLS: Bool = false
    var authToken: String = ""

    var url: URL? {
        var comps = URLComponents()
        comps.scheme = useTLS ? "https" : "http"
        comps.host = host
        comps.port = Int(port)
        comps.path = path.hasPrefix("/") ? path : "/\(path)"
        return comps.url
    }
}

// §6.6 connection state machine, trimmed to what a reachability check can honestly report.
// `.live` means the transport answered — it does NOT mean real trading data is flowing,
// since the server's actual tool contract (Appendix A) is still unconfirmed (spec §20 Q1).
enum MCPConnectionStatus: Equatable {
    case disabled
    case connecting
    case live
    case failed(String)
}
