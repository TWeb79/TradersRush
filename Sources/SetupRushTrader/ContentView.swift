import SwiftUI

struct ContentView: View {
    private let gateway: TradingGateway = MockTradingGateway()
    private let tickSize: Decimal = 0.25
    // Raised from 60 so long/short need visibly more pull before arming — more "space"
    // between the neutral zone and a committed direction, per explicit user feedback.
    private let armThreshold: CGFloat = 110

    // ⚠️ MOCK SIMULATION — set this to `false` (or delete simulateTick()/the onReceive
    // below it) once a real TradingGateway/MCP connection lands. A live gateway streams
    // real price/position/P&L updates itself; this local random-walk ticker and the
    // SL/TP/TSL/BE resolution in checkPositions() exist only so the bracket UI and the
    // win/loss alert are demoable before that connection exists.
    private let mockSimulationEnabled = true
    // EUR per 1.00 price move per contract — placeholder until a real InstrumentSpec
    // (tickValue/pointValue) exists; only used to size the mock P&L alert.
    private let mockPointValue: Decimal = 20

    @State private var candles: [Candle] = []
    @State private var footprint: [FootprintBar] = []
    @State private var ladder: [LadderLevel] = []
    @State private var startIndex: Double = 0
    @State private var candleWidth: CGFloat = 10
    @State private var showFootprint = false
    @State private var footprintMode: FootprintDisplayMode = .bidAsk
    @State private var ticketQty = 1
    @State private var bracket = BracketSettings()
    @State private var pnlAlert: PnLAlert?

    // Positions are real (not fabricated) results of the user's own BUY/SELL actions —
    // see Models.swift. Once mockSimulationEnabled is removed, these just stop closing
    // themselves; nothing here fakes account state the user didn't create.
    @State private var positions: [Position] = []
    @State private var orders: [WorkingOrder] = []

    // Keyboard (B/S) arm flow — unchanged, mouse-equivalent path per spec CH-25a.
    @State private var armed: ArmDirection?
    @State private var armExpiry: Date?

    // Trackpad two-finger joystick gesture — pull up/down from a fixed center dot;
    // releasing beyond the ring fires the trade, releasing inside it cancels.
    @State private var gestureActive = false
    @State private var gestureDelta: CGFloat = 0

    // Execution safety toggles (TR-26/OB-22 confirmation-policy pattern). Safer state is
    // the default for each; flipping to the riskier state shows a one-time risk alert and
    // reverts on cancel. Both are actually wired into every submission path via trigger().
    @State private var confirmationEnabled = true   // off = trades fire instantly, no Confirm step
    @State private var swipeTradeEnabled = false     // on = trackpad gesture can submit real orders
    @State private var pendingRiskAlert: RiskAlertKind?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SetupRush Trader")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("BETA 0.2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.borderSubtle, lineWidth: 1))
                // Honest data-source badge, not decoration — nothing on screen is live
                // yet, and silently showing synthetic prices as real would be exactly the
                // kind of fabricated-data problem the CX brief §12/§16 warns against.
                Text("MOCK DATA")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.warn.opacity(0.5), lineWidth: 1))
                Spacer(minLength: 12)
                // Horizontal scroll as a safety net: a plain HStack silently clips/hides
                // trailing content instead of shrinking it when the window gets narrow —
                // that's exactly what made the toggles "not visible". This keeps them
                // reachable at any window width instead of invisibly cut off.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        if showFootprint {
                            Picker("", selection: $footprintMode) {
                                ForEach(FootprintDisplayMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        Toggle("Footprint", isOn: $showFootprint)
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                            .foregroundStyle(Theme.textSecondary)
                        Divider().frame(height: 16).background(Theme.borderSubtle)
                        Toggle("Confirm", isOn: $confirmationEnabled)
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                            .foregroundStyle(Theme.textSecondary)
                            .onChange(of: confirmationEnabled) { old, new in
                                if old && !new { pendingRiskAlert = .disableConfirmation }
                            }
                        Toggle("Swipe trade", isOn: $swipeTradeEnabled)
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                            .foregroundStyle(Theme.textSecondary)
                            .onChange(of: swipeTradeEnabled) { old, new in
                                if !old && new { pendingRiskAlert = .enableSwipeTrade }
                            }
                    }
                    .fixedSize()
                }
                .frame(maxWidth: 560)
            }
            .padding(12)
            .background(Theme.bgSurface)
            .overlay(Rectangle().fill(Theme.borderSubtle).frame(height: 1), alignment: .bottom)

            if let armed {
                ArmedBanner(direction: armed, onConfirm: confirmArmed, onCancel: { self.armed = nil })
                    .transition(.opacity.animation(.easeOut(duration: 0.15))) // VD-04: motion ≤150ms
            }

            HStack(spacing: 0) {
                ZStack {
                    ChartView(candles: candles, footprint: footprint, positions: positions, pointValue: mockPointValue,
                              startIndex: $startIndex, candleWidth: $candleWidth,
                              showFootprint: showFootprint, footprintMode: footprintMode, tickSize: tickSize,
                              onGestureBegin: { if swipeTradeEnabled { gestureActive = true; gestureDelta = 0 } },
                              onGestureChange: { if swipeTradeEnabled { gestureDelta = $0 } },
                              onGestureEnd: { final in
                                  gestureActive = false
                                  if swipeTradeEnabled, let direction = armDirection(forDelta: final, threshold: armThreshold) {
                                      trigger(direction)
                                  }
                                  gestureDelta = 0
                              })
                    GestureArmOverlay(active: gestureActive, delta: gestureDelta, threshold: armThreshold)
                }
                Sidebar(ladder: ladder, lastPrice: candles.last?.c, qty: $ticketQty, bracket: $bracket,
                        onBuy: { trigger(.long) }, onSell: { trigger(.short) })
            }

            Dock(positions: positions, orders: orders, currentPrice: candles.last?.c, pointValue: mockPointValue)
        }
        .frame(minWidth: 1180, minHeight: 700)
        .background(Theme.bgBase)
        .overlay { if let pnlAlert { PnLAlertView(alert: pnlAlert) } }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if mockSimulationEnabled { simulateTick() }
        }
        .background(
            // Keyboard shortcuts B/S (mouse-user Arm Long/Short, spec CH-25a) and empty-area
            // dismiss. A hidden Button grabs the key event; SwiftUI has no raw key-down
            // modifier on macOS without this.
            Group {
                Button("") { trigger(.long) }.keyboardShortcut("b", modifiers: []).hidden()
                Button("") { trigger(.short) }.keyboardShortcut("s", modifiers: []).hidden()
                Button("") { confirmArmed() }.keyboardShortcut(.return, modifiers: []).hidden()
            }
        )
        .onAppear(perform: load)
        .onTapGesture { armed = nil } // dismiss on empty-area click, CH-25a
        .alert(item: $pendingRiskAlert) { kind in
            switch kind {
            case .enableSwipeTrade:
                Alert(title: Text("Swipe-to-trade risk"),
                      message: Text("A two-finger pull on the chart can submit a real order directly. An accidental swipe while panning or zooming could trigger an unintended trade."),
                      primaryButton: .destructive(Text("Enable")) {},
                      secondaryButton: .cancel(Text("Keep off")) { swipeTradeEnabled = false })
            case .disableConfirmation:
                Alert(title: Text("Confirmation disabled"),
                      message: Text("Trades will submit immediately with no Confirm step — including an armed swipe gesture. Mistaps or misreads won't be caught before the order is sent."),
                      primaryButton: .destructive(Text("Disable")) {},
                      secondaryButton: .cancel(Text("Keep required")) { confirmationEnabled = true })
            }
        }
    }

    // Single entry point every submission path (ticket, keyboard, swipe) routes through —
    // so the confirmationEnabled toggle is actually considered everywhere, not just one path.
    private func trigger(_ direction: ArmDirection) {
        if confirmationEnabled {
            arm(direction)
        } else {
            submit(direction)
        }
    }

    private func load() {
        candles = gateway.history(tickSize: tickSize, bars: 300)
        footprint = gateway.footprint(for: candles, tickSize: tickSize)
        if let last = candles.last?.c {
            ladder = gateway.ladder(around: last, tickSize: tickSize, levels: 12)
        }
        startIndex = Double(max(0, candles.count - 80))
        #if DEBUG
        armDirectionSelfCheck()
        #endif
    }

    private func arm(_ direction: ArmDirection) {
        armed = direction
        armExpiry = Date().addingTimeInterval(10)
        // 10s auto-disarm per TR-33 / CH-25a
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if let exp = armExpiry, exp <= Date() { armed = nil }
        }
    }

    private func confirmArmed() {
        guard let armed else { return }
        submit(armed)
        self.armed = nil
    }

    private func submit(_ direction: ArmDirection) {
        guard let entry = candles.last?.c else { return }
        let side: TradeSide = direction == .long ? .buy : .sell
        let position = Position(
            instrument: "MOCK-1", side: side, volume: ticketQty, avgPrice: entry,
            slPrice: bracket.slEnabled ? (direction == .long ? entry - bracket.slDistance : entry + bracket.slDistance) : nil,
            tpPrice: bracket.tpEnabled ? (direction == .long ? entry + bracket.tpDistance : entry - bracket.tpDistance) : nil,
            trailDistance: bracket.tslEnabled ? bracket.tslDistance : nil,
            beTrigger: bracket.beEnabled ? bracket.beTrigger : nil
        )
        positions.append(position)
        print("OPEN \(direction) \(ticketQty) @ \(entry) — mock, no live gateway connected yet")
    }

    // MOCK SIMULATION (see mockSimulationEnabled above): a local random walk standing in
    // for a real quote stream, just so the bracket below has something to react to.
    private func simulateTick() {
        guard var last = candles.last else { return }
        let step = Decimal(Int.random(in: -4...4)) * tickSize
        let newClose = last.c + step
        if newClose > last.h { last.h = newClose }
        if newClose < last.l { last.l = newClose }
        last.c = newClose
        candles[candles.count - 1] = last
        checkPositions(currentPrice: newClose)
    }

    // SL/TP/TSL/BE resolution (TR-43/TR-44 minimal scope). BE ratchets the stop to entry
    // once price moves favorably by beTrigger; TSL then keeps tightening it toward the
    // current price by trailDistance — in both cases the stop only ever tightens, never
    // loosens. Whichever of TP/SL is hit first closes the position and fires the alert.
    private func checkPositions(currentPrice: Decimal) {
        guard !positions.isEmpty else { return }
        var stillOpen: [Position] = []
        for var pos in positions {
            let favorable = pos.side == .buy ? currentPrice - pos.avgPrice : pos.avgPrice - currentPrice

            if let beTrigger = pos.beTrigger, !pos.beArmed, favorable >= beTrigger {
                pos.slPrice = pos.avgPrice
                pos.beArmed = true
            }
            if let trail = pos.trailDistance {
                let candidate = pos.side == .buy ? currentPrice - trail : currentPrice + trail
                if let currentSL = pos.slPrice {
                    pos.slPrice = pos.side == .buy ? max(currentSL, candidate) : min(currentSL, candidate)
                } else if favorable > 0 {
                    pos.slPrice = candidate
                }
            }

            var exitPrice: Decimal?
            if let tp = pos.tpPrice, (pos.side == .buy && currentPrice >= tp) || (pos.side == .sell && currentPrice <= tp) {
                exitPrice = tp
            } else if let sl = pos.slPrice, (pos.side == .buy && currentPrice <= sl) || (pos.side == .sell && currentPrice >= sl) {
                exitPrice = sl
            }

            if let exit = exitPrice {
                let pnlPoints = pos.side == .buy ? exit - pos.avgPrice : pos.avgPrice - exit
                showPnLAlert(pnlPoints * Decimal(pos.volume) * mockPointValue)
            } else {
                stillOpen.append(pos)
            }
        }
        positions = stillOpen
    }

    private func showPnLAlert(_ amount: Decimal) {
        let alert = PnLAlert(amount: amount)
        pnlAlert = alert
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if pnlAlert?.id == alert.id { pnlAlert = nil }
        }
    }
}

struct PnLAlert: Identifiable, Equatable {
    let id = UUID()
    let amount: Decimal
}

private enum RiskAlertKind: String, Identifiable {
    case enableSwipeTrade, disableConfirmation
    var id: String { rawValue }
}

// Collects money in green / stings in red — a deliberate, explicitly-requested exception
// to the CX brief's usual "no celebratory profit animations" stance for this one moment.
private struct PnLAlertView: View {
    let alert: PnLAlert
    @State private var popped = false
    @State private var floated = false

    private var positive: Bool { alert.amount >= 0 }
    private var tint: Color { positive ? Theme.bull : Theme.bear }

    var body: some View {
        Text("\(positive ? "+" : "")\(amountString) EUR")
            .font(.system(size: 34, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Theme.bgElevated.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.6), lineWidth: 1))
            .scaleEffect(popped ? 1.0 : 0.4)
            .offset(y: floated ? -50 : 0)
            .opacity(floated ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { popped = true }
                withAnimation(.easeOut(duration: 1.2).delay(0.5)) { floated = true }
            }
    }

    private var amountString: String {
        alert.amount.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

// Pure so it's trivially checkable: negative delta past the threshold = long (pulled up),
// positive = short (pulled down), anything inside the threshold = no trade.
func armDirection(forDelta delta: CGFloat, threshold: CGFloat) -> ArmDirection? {
    guard abs(delta) > threshold else { return nil }
    return delta < 0 ? .long : .short
}

#if DEBUG
private func armDirectionSelfCheck() {
    assert(armDirection(forDelta: -150, threshold: 110) == .long)
    assert(armDirection(forDelta: 150, threshold: 110) == .short)
    assert(armDirection(forDelta: 50, threshold: 110) == nil)
    assert(armDirection(forDelta: -50, threshold: 110) == nil)
}
#endif

private struct ArmedBanner: View {
    let direction: ArmDirection
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text(direction == .long ? "▲ Armed long — click or Return to confirm" : "▼ Armed short — click or Return to confirm")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Confirm", action: onConfirm)
            Button("Cancel", action: onCancel)
        }
        .padding(12)
        .background((direction == .long ? Theme.bull : Theme.bear).opacity(0.85))
    }
}

// Pull-to-arm feedback: a dead-zone ring fixed at the chart's center; pulling past it
// grows a directional arrow, release decides trigger vs cancel (ContentView.armDirection).
// Restyled per the CX brief §4/§14 (no glow/shadow effects, no bounce/spring motion,
// reduced-motion-aware) — the gesture itself stays, the glowing/bouncy treatment doesn't.
// Fully decorative/non-hit-testing — the trackpad capture view owns the actual gesture.
private struct GestureArmOverlay: View {
    let active: Bool
    let delta: CGFloat
    let threshold: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var magnitude: CGFloat { min(abs(delta) / threshold, 1.3) }
    private var pullFraction: CGFloat { min(abs(delta) / threshold, 1.0) } // 0 at center, 1 at the ring's border
    private var armed: Bool { abs(delta) > threshold }
    private var isLong: Bool { delta < 0 }
    private var tint: Color { isLong ? Theme.bull : Theme.bear }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.bgElevated.opacity(0.7))
                .overlay(Circle().stroke(armed ? tint : Theme.borderSubtle, lineWidth: armed ? 2 : 1))
                .frame(width: threshold * 2, height: threshold * 2)

            // Knob: grey at center, blends to the full long/short color by 80% of the way
            // to the ring's border, then stays that color — a continuous "how committed is
            // this pull" read, not a hard snap at the arm threshold.
            let knobTravel = pullFraction * (threshold - 10)
            let colorMix = min(pullFraction / 0.8, 1.0)
            ZStack {
                Circle().fill(Theme.textSecondary)
                Circle().fill(tint).opacity(colorMix)
            }
            .frame(width: 14, height: 14)
            .offset(y: isLong ? -knobTravel : knobTravel)

            if magnitude > 0.05 {
                // Starts right at the ring's edge and travels further outward (in the
                // pull direction) as magnitude grows, growing in size as it goes.
                let travel = magnitude * threshold * 0.8
                let offset = threshold + travel
                Image(systemName: isLong ? "arrow.up" : "arrow.down")
                    .font(.system(size: 16 + magnitude * 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .offset(y: isLong ? -offset : offset)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: delta)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
        .allowsHitTesting(false)
    }
}
