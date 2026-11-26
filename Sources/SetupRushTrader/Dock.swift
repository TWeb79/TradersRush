import SwiftUI

// CX brief §5 "Position management workspace" + §16 empty states. positions/orders are
// real (always empty here — see Models.swift) so this never fabricates financial state,
// just shows the dock structure and its honest empty state.
struct Dock: View {
    let positions: [Position]
    let orders: [WorkingOrder]

    private enum Tab: String, CaseIterable { case positions = "Positions", orders = "Orders" }
    @State private var tab: Tab = .positions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                tabButton(.positions, count: positions.count)
                tabButton(.orders, count: orders.count)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8)

            Group {
                switch tab {
                case .positions:
                    emptyState(positions.isEmpty, "No open positions", "Orders you place will appear here.")
                case .orders:
                    emptyState(orders.isEmpty, "No working orders", "Pending limit/stop orders will appear here.")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
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

    private func emptyState(_ isEmpty: Bool, _ title: String, _ subtitle: String) -> some View {
        Group {
            if isEmpty {
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .padding(.vertical, 14)
            }
        }
    }
}
