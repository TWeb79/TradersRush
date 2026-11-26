import SwiftUI

// CX brief §5 "Position management workspace" + §16 empty states. positions/orders are
// real (never fabricated — see Models.swift): rows only ever reflect the user's own
// simulated trades, never invented account state.
struct Dock: View {
    let positions: [Position]
    let orders: [WorkingOrder]
    let currentPrice: Decimal?
    let pointValue: Decimal

    private enum Tab: String, CaseIterable { case positions = "Positions", orders = "Orders" }
    @State private var tab: Tab = .positions

    // Fixed content height (not minHeight) — previously nothing bounded this once rows
    // existed, so a growing list could push the window/screen bounds. A ScrollView inside
    // a fixed frame keeps the dock's footprint constant regardless of how many rows exist.
    private let contentHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                tabButton(.positions, count: positions.count)
                tabButton(.orders, count: orders.count)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

            ScrollView {
                switch tab {
                case .positions:
                    if positions.isEmpty {
                        emptyState("No open positions", "Orders you place will appear here.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(positions) { PositionRow(position: $0, currentPrice: currentPrice, pointValue: pointValue) }
                        }
                    }
                case .orders:
                    if orders.isEmpty {
                        emptyState("No working orders", "Pending limit/stop orders will appear here.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(orders) { OrderRow(order: $0) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: contentHeight)
        }
        .frame(height: contentHeight + 36)
        .background(Theme.bgSurface)
        .overlay(Rectangle().fill(Theme.borderSubtle).frame(height: 1), alignment: .top)
    }

    private func tabButton(_ t: Tab, count: Int) -> some View {
        Button {
            tab = t
        } label: {
            Text("\(t.rawValue) (\(count))")
                .font(.system(size: 11, weight: tab == t ? .semibold : .regular))
                .foregroundStyle(tab == t ? Theme.textPrimary : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

private struct PositionRow: View {
    let position: Position
    let currentPrice: Decimal?
    let pointValue: Decimal

    private var pnl: Decimal? {
        guard let currentPrice else { return nil }
        let points = position.side == .buy ? currentPrice - position.avgPrice : position.avgPrice - currentPrice
        return points * Decimal(position.volume) * pointValue
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(position.side == .buy ? "BUY" : "SELL")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(position.side == .buy ? Theme.bull : Theme.bear)
                .frame(width: 36, alignment: .leading)
            Text("\(position.volume) @ \(priceString(position.avgPrice))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            if let sl = position.slPrice {
                Text("SL \(priceString(sl))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.bear.opacity(0.8))
            }
            if let tp = position.tpPrice {
                Text("TP \(priceString(tp))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.bull.opacity(0.8))
            }
            Spacer()
            if let pnl {
                Text("\(pnl >= 0 ? "+" : "")\(priceString(pnl)) EUR")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pnl >= 0 ? Theme.bull : Theme.bear)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func priceString(_ p: Decimal) -> String {
        p.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private struct OrderRow: View {
    let order: WorkingOrder

    var body: some View {
        HStack(spacing: 10) {
            Text(order.side == .buy ? "BUY" : "SELL")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(order.side == .buy ? Theme.bull : Theme.bear)
            Text("\(order.type) \(order.volume) @ \(priceString(order.price))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func priceString(_ p: Decimal) -> String {
        p.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}
