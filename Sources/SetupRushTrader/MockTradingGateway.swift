import Foundation

// CH-37: synthetic data so chart/gestures/footprint are exercisable before the real MCP
// endpoint (host/port TBD) exists. Stays as a DEBUG/preview data source after that lands.
struct MockTradingGateway: TradingGateway {
    func history(tickSize: Decimal, bars: Int) -> [Candle] {
        var price = Decimal(5400)
        var candles: [Candle] = []
        let now = Date()
        for i in 0..<bars {
            let o = price
            let steps = (0..<20).map { _ in Int.random(in: -3...3) }
            var h = o, l = o, c = o
            for s in steps {
                c += Decimal(s) * tickSize
                if c > h { h = c }
                if c < l { l = c }
            }
            price = c
            let volume = Int.random(in: 200...2000)
            candles.append(Candle(time: now.addingTimeInterval(TimeInterval((i - bars) * 60)),
                                   o: o, h: h, l: l, c: c, volume: volume, isClosed: true))
        }
        return candles
    }

    // ponytail: footprint bins are re-synthesized from the candle's range rather than real
    // per-trade aggregation (no Trade stream yet) — swap for Trade-based aggregation (spec CH-34)
    // once subscribe_trades exists.
    func footprint(for candles: [Candle], tickSize: Decimal) -> [FootprintBar] {
        candles.map { candle in
            var bins: [PriceBin] = []
            var p = candle.l
            while p <= candle.h {
                let bid = Int.random(in: 0...candle.volume / 6)
                let ask = Int.random(in: 0...candle.volume / 6)
                bins.append(PriceBin(price: p, bidVolume: bid, askVolume: ask))
                p += tickSize
            }
            return FootprintBar(time: candle.time, priceBins: bins)
        }
    }

    // OB-01 minimal scope: synthetic ladder centered on the last close, same "MOCK DATA"
    // honesty framing as history()/footprint() — not a stand-in for real account/position state.
    func ladder(around last: Decimal, tickSize: Decimal, levels: Int) -> [LadderLevel] {
        (-levels...levels).reversed().map { i in
            let price = last + Decimal(i) * tickSize
            return LadderLevel(
                price: price,
                bidSize: i < 0 ? Int.random(in: 20...400) : 0,
                askSize: i > 0 ? Int.random(in: 20...400) : 0
            )
        }
    }
}
