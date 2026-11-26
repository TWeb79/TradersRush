import SwiftUI

// CH-01/02/34: candlestick chart with a toggleable Footprint (bid/ask/delta per bin, CH-34
// minimal scope — POC/CVD/absorption overlays deferred per spec §7.1.7). Footprint has two
// zoom tiers: zoomed out shows compact colored bars (legible at scale), zoomed in (candleWidth
// past detailThreshold) reveals per-price-level numbers — "zoom in to see the orderflow."
struct ChartView: View {
    let candles: [Candle]
    let footprint: [FootprintBar]
    @Binding var startIndex: Double
    @Binding var candleWidth: CGFloat
    var showFootprint: Bool
    var footprintMode: FootprintDisplayMode
    var tickSize: Decimal
    var onGestureBegin: () -> Void
    var onGestureChange: (CGFloat) -> Void
    var onGestureEnd: (CGFloat) -> Void

    private let minWidth: CGFloat = 4, maxWidth: CGFloat = 90
    // Raised from 70 — the old threshold left barely enough width for 3-digit numbers at a
    // legible size, which is exactly what made the detailed footprint unreadable.
    private let detailThreshold: CGFloat = 85

    var body: some View {
        Canvas { context, size in
            let visibleCount = max(1, Int(size.width / candleWidth))
            let maxStart = max(0, candles.count - visibleCount)
            let start = min(max(0, Int(startIndex)), maxStart)
            let end = min(candles.count, start + visibleCount)
            guard start < end else { return }
            let visible = candles[start..<end]

            let highs = visible.map { $0.h }, lows = visible.map { $0.l }
            guard let maxH = highs.max(), let minL = lows.min(), maxH > minL else { return }
            let priceSpan = Double(truncating: (maxH - minL) as NSNumber)

            func y(_ price: Decimal) -> CGFloat {
                let v = Double(truncating: (price - minL) as NSNumber)
                return size.height * (1 - CGFloat(v / priceSpan))
            }

            for (i, candle) in visible.enumerated() {
                let x = CGFloat(i) * candleWidth + candleWidth / 2
                let bullish = candle.c >= candle.o
                let color: Color = bullish ? Theme.bull : Theme.bear

                if showFootprint, start + i < footprint.count {
                    let bar = footprint[start + i]
                    if candleWidth >= detailThreshold {
                        drawDetailedFootprint(bar, x: x, context: context, y: y)
                    } else {
                        drawCompactFootprint(bar, x: x, context: context, y: y)
                    }
                } else {
                    var wick = Path()
                    wick.move(to: CGPoint(x: x, y: y(candle.h)))
                    wick.addLine(to: CGPoint(x: x, y: y(candle.l)))
                    context.stroke(wick, with: .color(color), lineWidth: 1)

                    let bodyTop = y(max(candle.o, candle.c))
                    let bodyBottom = y(min(candle.o, candle.c))
                    let body = CGRect(x: x - candleWidth * 0.35, y: bodyTop,
                                       width: candleWidth * 0.7, height: max(1, bodyBottom - bodyTop))
                    context.fill(Path(body), with: .color(color))
                }
            }

            // CH-06 (minimal): last price tag on the right axis, tinted by tick direction —
            // price-space anchor so the hero (price action) always reads at a glance (VD-02 tabular digits).
            if let last = visible.last {
                let lastY = y(last.c)
                let tagColor = last.c >= last.o ? Theme.bull : Theme.bear
                context.fill(Path(CGRect(x: size.width - 58, y: lastY - 9, width: 58, height: 18)), with: .color(tagColor))
                context.draw(
                    Text(priceString(last.c)).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(Theme.bgBase),
                    at: CGPoint(x: size.width - 29, y: lastY)
                )
            }
        }
        .background(Theme.bgBase)
        .overlay(
            TrackpadCapture(
                onPanX: { dx in
                    startIndex = min(max(0, startIndex - dx / candleWidth), Double(max(0, candles.count - 1)))
                },
                onZoom: { magnification, anchorX in
                    let oldWidth = candleWidth
                    let newWidth = min(maxWidth, max(minWidth, oldWidth * (1 + magnification)))
                    guard newWidth != oldWidth else { return }
                    // Keep the candle under the pinch stationary: find its fractional index
                    // at the old width, then re-derive startIndex so it lands at the same x.
                    let anchorIndex = startIndex + Double(anchorX / oldWidth)
                    candleWidth = newWidth
                    startIndex = max(0, anchorIndex - Double(anchorX / newWidth))
                },
                onGestureBegin: onGestureBegin,
                onGestureChange: onGestureChange,
                onGestureEnd: onGestureEnd
            )
        )
    }

    // Zoomed-out footprint: no room for numbers, but the mode picker must still visibly do
    // something at every zoom level — previously both modes rendered identically here
    // (always delta-colored), so switching the picker looked broken at normal zoom.
    private func drawCompactFootprint(_ bar: FootprintBar, x: CGFloat, context: GraphicsContext, y: (Decimal) -> CGFloat) {
        switch footprintMode {
        case .bidAsk:
            for bin in bar.priceBins {
                let binY = y(bin.price)
                let bidW = CGFloat(bin.bidVolume) / 40
                let askW = CGFloat(bin.askVolume) / 40
                if bidW > 0.3 {
                    context.fill(Path(CGRect(x: x - bidW, y: binY - 2, width: bidW, height: 3)), with: .color(Theme.bear.opacity(0.75)))
                }
                if askW > 0.3 {
                    context.fill(Path(CGRect(x: x, y: binY - 2, width: askW, height: 3)), with: .color(Theme.bull.opacity(0.75)))
                }
            }
        case .delta:
            for bin in bar.priceBins {
                let binY = y(bin.price)
                let w = CGFloat(abs(bin.delta)) / 40
                guard w > 0.3 else { continue }
                let color = (bin.delta >= 0 ? Theme.bull : Theme.bear).opacity(0.8)
                let rect = bin.delta >= 0
                    ? CGRect(x: x, y: binY - 2, width: w, height: 3)
                    : CGRect(x: x - w, y: binY - 2, width: w, height: 3)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }

    // CH-34: per-price-level bid/ask/delta, built causally from the Trade stream per the
    // DeltaTrader playbook §11 construction (volume[p] split by aggressor side). Bid×Ask
    // mode shows both sides as numbers (never color-only, VD-01); Delta mode shows the net
    // with a diverging bar off a center zero-line.
    private func drawDetailedFootprint(_ bar: FootprintBar, x: CGFloat, context: GraphicsContext, y: (Decimal) -> CGFloat) {
        guard let first = bar.priceBins.first else { return }
        let step = bar.priceBins.count > 1 ? bar.priceBins[1].price - first.price : tickSize
        let rowHeight = abs(y(first.price) - y(first.price + step))
        // VD-02 wants ladder-type numerics at 13–14pt; the old 8–11pt range (gated at a
        // 9px row) was the "not readable at all" complaint. Only render once there's
        // actually room for that size, rather than shrinking text to fit.
        guard rowHeight >= 15 else { return }
        let fontSize = min(14, max(12, rowHeight - 5))
        let maxAbsDelta = max(bar.priceBins.map { abs($0.delta) }.max() ?? 1, 1)

        for bin in bar.priceBins {
            let rowBottom = y(bin.price)
            let rowTop = rowBottom - rowHeight
            let midY = (rowTop + rowBottom) / 2

            var divider = Path() // shared zero-line / price-level separator for both modes
            divider.move(to: CGPoint(x: x, y: rowTop))
            divider.addLine(to: CGPoint(x: x, y: rowBottom))
            context.stroke(divider, with: .color(Theme.borderSubtle), lineWidth: 0.5)

            switch footprintMode {
            case .bidAsk:
                context.draw(
                    Text("\(bin.bidVolume)").font(.system(size: fontSize, design: .monospaced)).foregroundColor(Theme.bear),
                    at: CGPoint(x: x - candleWidth * 0.27, y: midY)
                )
                context.draw(
                    Text("\(bin.askVolume)").font(.system(size: fontSize, design: .monospaced)).foregroundColor(Theme.bull),
                    at: CGPoint(x: x + candleWidth * 0.27, y: midY)
                )
            case .delta:
                let frac = CGFloat(abs(bin.delta)) / CGFloat(maxAbsDelta)
                let barLen = frac * candleWidth * 0.4
                let barColor = (bin.delta >= 0 ? Theme.bull : Theme.bear).opacity(0.45)
                let barRect = bin.delta >= 0
                    ? CGRect(x: x, y: rowTop + 1, width: barLen, height: max(1, rowHeight - 2))
                    : CGRect(x: x - barLen, y: rowTop + 1, width: barLen, height: max(1, rowHeight - 2))
                context.fill(Path(barRect), with: .color(barColor))
                context.draw(
                    Text("\(bin.delta >= 0 ? "+" : "")\(bin.delta)")
                        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                        .foregroundColor(bin.delta >= 0 ? Theme.bull : Theme.bear),
                    at: CGPoint(x: x, y: midY)
                )
            }
        }
    }

    // Locale-fixed (not .formatted(), which follows system locale, e.g. "5.371,25" on
    // a German Mac) — trading numerics must read the same regardless of locale (UX-U3).
    private func priceString(_ price: Decimal) -> String {
        price.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}
