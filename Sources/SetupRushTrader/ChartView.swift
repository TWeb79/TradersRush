import SwiftUI

// CH-01/02/34: candlestick chart with a toggleable Footprint (bid/ask/delta per bin, CH-34
// minimal scope — POC/CVD/absorption overlays deferred per spec §7.1.7). Footprint has two
// zoom tiers: zoomed out shows compact colored bars (legible at scale), zoomed in (candleWidth
// past detailThreshold) reveals per-price-level numbers — "zoom in to see the orderflow."
struct ChartView: View {
    let candles: [Candle]
    let footprint: [FootprintBar]
    let positions: [Position]
    let pointValue: Decimal
    @Binding var startIndex: Double
    @Binding var candleWidth: CGFloat
    var showFootprint: Bool
    var footprintMode: FootprintDisplayMode
    var extendedView: Bool
    var tickSize: Decimal
    var onGestureBegin: () -> Void
    var onGestureChange: (CGFloat) -> Void
    var onGestureEnd: (CGFloat) -> Void

    private let minWidth: CGFloat = 4
    // Raised from 90: bin row height is driven by vertical price-span auto-scale (fewer
    // visible candles -> smaller aggregate high/low range -> taller rows), not by
    // candleWidth directly. 90 didn't let you zoom in far enough horizontally to shrink
    // that range down to readable bin heights — this does.
    private let maxWidth: CGFloat = 400
    // Raised from 70 — the old threshold left barely enough width for 3-digit numbers at a
    // legible size, which is exactly what made the detailed footprint unreadable.
    private let detailThreshold: CGFloat = 85

    // Both the renderer and the pinch-zoom anchor must clamp `startIndex` the exact same
    // way, or the anchor math runs against a `start` that was never actually on screen.
    // This was the recurring "zoom doesn't work" bug: the old onZoom closure couldn't see
    // the chart's pixel width (only the Canvas draw closure had it), so it used the raw,
    // unclamped startIndex — wrong whenever that exceeded maxStart, which is exactly the
    // common case right after launch before any panning.
    private func clampedStart(_ width: CGFloat, chartWidth: CGFloat) -> Int {
        let visibleCount = max(1, Int(chartWidth / width))
        let maxStart = max(0, candles.count - visibleCount)
        return min(max(0, Int(startIndex)), maxStart)
    }

    // Extended View (inspired by a reference order-flow dashboard, replicated only where
    // it's buildable from data this prototype already has — no multi-day session/VAH-VAL
    // history, so the "context" panel from that reference isn't reproduced here) reserves
    // a right-edge panel for the session volume/delta profile, shrinking the candle area.
    private var profileWidth: CGFloat { extendedView ? 90 : 0 }

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
        Canvas { context, size in
            let chartWidth = size.width - profileWidth
            let visibleCount = max(1, Int(chartWidth / candleWidth))
            let start = clampedStart(candleWidth, chartWidth: chartWidth)
            let end = min(candles.count, start + visibleCount)
            guard start < end else { return }
            let visible = candles[start..<end]

            // Extend the price range to cover every open position's entry/SL/TP, not just
            // visible candle highs/lows — otherwise a line can silently scroll off-screen
            // the moment price moves away from it instead of keeping it in view.
            var highs = visible.map { $0.h }, lows = visible.map { $0.l }
            for pos in positions {
                highs.append(pos.avgPrice); lows.append(pos.avgPrice)
                if let sl = pos.slPrice { highs.append(sl); lows.append(sl) }
                if let tp = pos.tpPrice { highs.append(tp); lows.append(tp) }
            }
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

            // CH-10..19a (minimal): entry/SL/TP lines pinned in price-space. Positions are
            // only ever what checkPositions() currently holds open (ContentView), so a
            // closed trade disappearing from the chart is just this array no longer
            // containing it — no separate removal logic needed here.
            for pos in positions {
                drawPositionOverlay(pos, size: size, context: context, y: y, currentPrice: visible.last?.c)
            }

            // CH-06 (minimal): last price tag on the right axis, tinted by tick direction —
            // price-space anchor so the hero (price action) always reads at a glance (VD-02 tabular digits).
            if let last = visible.last {
                let lastY = y(last.c)
                let tagColor = last.c >= last.o ? Theme.bull : Theme.bear
                context.fill(Path(CGRect(x: chartWidth - 58, y: lastY - 9, width: 58, height: 18)), with: .color(tagColor))
                context.draw(
                    Text(priceString(last.c)).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(Theme.bgBase),
                    at: CGPoint(x: chartWidth - 29, y: lastY)
                )
            }

            if extendedView {
                drawVWAP(visible, width: size.width, context: context, y: y)
                let footSlice = start < footprint.count ? footprint[start..<min(end, footprint.count)] : []
                drawSessionProfile(footSlice, x0: chartWidth, width: profileWidth, context: context, y: y)
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
                    // Must match the render formula exactly: x = (i_global - start) * candleWidth
                    // + candleWidth/2, using the same clamped `start` the renderer actually used.
                    let chartWidth = geo.size.width - profileWidth
                    let start = Double(clampedStart(oldWidth, chartWidth: chartWidth))
                    let anchorGlobalIndex = start + Double(anchorX / oldWidth) - 0.5
                    candleWidth = newWidth
                    startIndex = max(0, anchorGlobalIndex - Double(anchorX / newWidth) + 0.5)
                },
                onGestureBegin: onGestureBegin,
                onGestureChange: onGestureChange,
                onGestureEnd: onGestureEnd
            )
        )
        if extendedView {
            Divider().background(Theme.borderSubtle)
            Canvas { context, size in
                drawFlowStrip(context: context, size: size, chartWidth: geo.size.width - profileWidth)
            }
            .frame(height: 110)
            .background(Theme.bgBase)
        }
        }
        }
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
        // Scales with the box, not capped at spec's 13-14pt ladder minimum — once you've
        // zoomed in far enough to get tall rows, the numbers should actually fill them.
        let fontSize = min(26, max(12, rowHeight * 0.4))
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

    // CH-10/12/17/18: entry line (grey, dashed) with an id + live P&L chip, plus SL (red)
    // and TP (green) lines. SL moves live when BE/TSL ratchets it in ContentView — this
    // just draws whatever pos.slPrice currently is, so it tracks automatically.
    private func drawPositionOverlay(_ pos: Position, size: CGSize, context: GraphicsContext, y: (Decimal) -> CGFloat, currentPrice: Decimal?) {
        func dashedLine(at price: Decimal, color: Color) {
            var line = Path()
            let py = y(price)
            line.move(to: CGPoint(x: 0, y: py))
            line.addLine(to: CGPoint(x: size.width, y: py))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }

        dashedLine(at: pos.avgPrice, color: Theme.textSecondary)
        if let sl = pos.slPrice { dashedLine(at: sl, color: Theme.bear) }
        if let tp = pos.tpPrice { dashedLine(at: tp, color: Theme.bull) }

        let shortId = pos.id.uuidString.prefix(6)
        let sideGlyph = pos.side == .buy ? "▲" : "▼"
        var pnlText = "—"
        var pnlColor = Theme.textSecondary
        if let currentPrice {
            let points = pos.side == .buy ? currentPrice - pos.avgPrice : pos.avgPrice - currentPrice
            let pnl = points * Decimal(pos.volume) * pointValue
            pnlText = "\(pnl >= 0 ? "+" : "")\(priceString(pnl)) EUR"
            pnlColor = pnl >= 0 ? Theme.bull : Theme.bear
        }

        let entryY = y(pos.avgPrice)
        let label = "#\(shortId) \(sideGlyph) \(pnlText)"
        context.fill(Path(CGRect(x: 6, y: entryY - 9, width: 150, height: 18)), with: .color(Theme.bgElevated.opacity(0.92)))
        context.draw(
            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(pnlColor),
            at: CGPoint(x: 81, y: entryY)
        )

        if let sl = pos.slPrice {
            let slY = y(sl)
            context.fill(Path(CGRect(x: size.width - 118, y: slY - 8, width: 60, height: 16)), with: .color(Theme.bear.opacity(0.85)))
            context.draw(Text("SL \(priceString(sl))").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.bgBase),
                         at: CGPoint(x: size.width - 88, y: slY))
        }
        if let tp = pos.tpPrice {
            let tpY = y(tp)
            context.fill(Path(CGRect(x: size.width - 118, y: tpY - 8, width: 60, height: 16)), with: .color(Theme.bull.opacity(0.85)))
            context.draw(Text("TP \(priceString(tp))").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.bgBase),
                         at: CGPoint(x: size.width - 88, y: tpY))
        }
    }

    // Extended View: volume-weighted average price over the visible window (no real
    // session boundary in mock data, so "session" here just means "currently visible" —
    // a deliberate scope cut from the reference dashboard's real session-anchored VWAP).
    private func drawVWAP(_ bars: ArraySlice<Candle>, width: CGFloat, context: GraphicsContext, y: (Decimal) -> CGFloat) {
        var sumPV: Decimal = 0, sumV: Decimal = 0
        for b in bars {
            let typical = (b.h + b.l + b.c) / 3
            sumPV += typical * Decimal(b.volume)
            sumV += Decimal(b.volume)
        }
        guard sumV > 0 else { return }
        let vwap = sumPV / sumV
        let py = y(vwap)
        var line = Path()
        line.move(to: CGPoint(x: 0, y: py))
        line.addLine(to: CGPoint(x: width, y: py))
        context.stroke(line, with: .color(Theme.warn), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        context.draw(Text("VWAP").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.warn), at: CGPoint(x: 24, y: py - 8))
    }

    // Extended View: session volume/delta profile along the chart's right edge — same
    // per-price-level totals the footprint already computes, just summed across every
    // visible bar instead of shown per-candle. Mirrors the reference dashboard's profile
    // panel, built entirely from data this prototype already has.
    private func drawSessionProfile(_ bars: ArraySlice<FootprintBar>, x0: CGFloat, width: CGFloat, context: GraphicsContext, y: (Decimal) -> CGFloat) {
        guard width > 0 else { return }
        var totals: [Decimal: (vol: Int, delta: Int)] = [:]
        for bar in bars {
            for bin in bar.priceBins {
                var t = totals[bin.price] ?? (0, 0)
                t.vol += bin.bidVolume + bin.askVolume
                t.delta += bin.delta
                totals[bin.price] = t
            }
        }
        let rows = totals.map { (price: $0.key, vol: $0.value.vol, delta: $0.value.delta) }.sorted { $0.price < $1.price }
        guard let first = rows.first else { return }
        let step = rows.count > 1 ? rows[1].price - first.price : tickSize
        let rowHeight = abs(y(first.price) - y(first.price + step))
        guard rowHeight >= 1 else { return }

        let maxVol = max(rows.map(\.vol).max() ?? 1, 1)
        let maxDelta = max(rows.map { abs($0.delta) }.max() ?? 1, 1)
        let volW = width * 0.5, deltaW = width * 0.42, zero = x0 + 4 + volW + 6 + deltaW / 2

        var axis = Path()
        axis.move(to: CGPoint(x: zero, y: 0))
        axis.addLine(to: CGPoint(x: zero, y: 100_000)) // clipped by the canvas bounds anyway
        context.stroke(axis, with: .color(Theme.borderSubtle), lineWidth: 1)

        let showNumbers = rowHeight >= 10
        for row in rows {
            let rowBottom = y(row.price)
            let rowTop = rowBottom - rowHeight
            let h = max(1, rowHeight - 1)
            let volBarW = volW * CGFloat(row.vol) / CGFloat(maxVol)
            context.fill(Path(CGRect(x: x0 + 4, y: rowTop, width: volBarW, height: h)), with: .color(Theme.textSecondary.opacity(0.7)))
            let dW = deltaW / 2 * CGFloat(abs(row.delta)) / CGFloat(maxDelta)
            let dColor = (row.delta >= 0 ? Theme.bull : Theme.bear).opacity(0.85)
            let dRect = row.delta >= 0 ? CGRect(x: zero, y: rowTop, width: dW, height: h) : CGRect(x: zero - dW, y: rowTop, width: dW, height: h)
            context.fill(Path(dRect), with: .color(dColor))
            if showNumbers, abs(row.delta) >= maxDelta / 4 {
                let label = "\(row.delta >= 0 ? "+" : "")\(row.delta)"
                context.draw(Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(dColor),
                             at: CGPoint(x: row.delta >= 0 ? zero + dW + 2 : zero - dW - 2, y: rowTop + h / 2))
            }
        }
        context.draw(Text("volume").font(.system(size: 9)).foregroundColor(Theme.textSecondary), at: CGPoint(x: x0 + 4 + volW / 2, y: 10))
        context.draw(Text("delta").font(.system(size: 9)).foregroundColor(Theme.textSecondary), at: CGPoint(x: zero, y: 10))
    }

    // Extended View flow strip: CVD (cumulative, over the visible window — see VWAP's
    // same session-boundary caveat), bar volume, bar delta. Shares the main chart's
    // column positions exactly so bars line up between the two canvases.
    private func drawFlowStrip(context: GraphicsContext, size: CGSize, chartWidth: CGFloat) {
        let visibleCount = max(1, Int(chartWidth / candleWidth))
        let start = clampedStart(candleWidth, chartWidth: chartWidth)
        let end = min(candles.count, start + visibleCount)
        guard start < end else { return }
        let vis = candles[start..<end]
        let footSlice = start < footprint.count ? footprint[start..<min(end, footprint.count)] : []
        let deltas: [Int] = footSlice.map { bar in bar.priceBins.reduce(0) { $0 + $1.delta } }
        var cvd: [Int] = []
        var running = 0
        for d in deltas { running += d; cvd.append(running) }

        let maxVol = max(vis.map(\.volume).max() ?? 1, 1)
        let maxAbsDelta = max(deltas.map(abs).max() ?? 1, 1)
        let maxAbsCVD = max(cvd.map(abs).max() ?? 1, 1)
        let x0 = chartWidth - CGFloat(vis.count) * candleWidth

        let cvdTop: CGFloat = 4, cvdH = size.height * 0.45
        let volTop = cvdTop + cvdH + 6, volH = size.height * 0.2
        let deltaTop = volTop + volH + 6, deltaH = size.height * 0.2

        var zero = Path()
        let zy = cvdTop + cvdH / 2
        zero.move(to: CGPoint(x: 0, y: zy))
        zero.addLine(to: CGPoint(x: size.width, y: zy))
        context.stroke(zero, with: .color(Theme.borderSubtle), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        var cvdPath = Path()
        for (i, v) in cvd.enumerated() {
            let x = x0 + CGFloat(i) * candleWidth + candleWidth / 2
            let yy = zy - CGFloat(v) / CGFloat(maxAbsCVD) * (cvdH / 2)
            if i == 0 { cvdPath.move(to: CGPoint(x: x, y: yy)) } else { cvdPath.addLine(to: CGPoint(x: x, y: yy)) }
        }
        context.stroke(cvdPath, with: .color(Theme.accent), lineWidth: 1.5)
        let cvdLabel = "CVD \(cvd.last.map { ($0 >= 0 ? "+" : "") + "\($0)" } ?? "—")"
        context.draw(Text(cvdLabel).font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.accent), at: CGPoint(x: 48, y: cvdTop + 8))

        for (i, b) in vis.enumerated() {
            let x = x0 + CGFloat(i) * candleWidth + 1, w = max(1, candleWidth - 3)
            let h = CGFloat(b.volume) / CGFloat(maxVol) * volH
            context.fill(Path(CGRect(x: x, y: volTop + volH - h, width: w, height: h)), with: .color(Theme.textSecondary.opacity(0.7)))
        }
        context.draw(Text("volume").font(.system(size: 9)).foregroundColor(Theme.textSecondary), at: CGPoint(x: 28, y: volTop + 9))

        for (i, d) in deltas.enumerated() {
            let x = x0 + CGFloat(i) * candleWidth + 1, w = max(1, candleWidth - 3)
            let h = CGFloat(abs(d)) / CGFloat(maxAbsDelta) * deltaH
            let rect = d >= 0 ? CGRect(x: x, y: deltaTop + deltaH - h, width: w, height: h) : CGRect(x: x, y: deltaTop, width: w, height: h)
            context.fill(Path(rect), with: .color((d >= 0 ? Theme.bull : Theme.bear).opacity(0.85)))
        }
        context.draw(Text("bar delta").font(.system(size: 9)).foregroundColor(Theme.textSecondary), at: CGPoint(x: 34, y: deltaTop + 9))
    }

    // Locale-fixed (not .formatted(), which follows system locale, e.g. "5.371,25" on
    // a German Mac) — trading numerics must read the same regardless of locale (UX-U3).
    private func priceString(_ price: Decimal) -> String {
        price.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}
