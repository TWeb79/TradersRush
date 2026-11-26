import SwiftUI

// CX brief §5 "Order-flow and execution workspace" / spec OB-20 Quick-Execution panel +
// OB-01 ladder, minimal scope. BUY/SELL reuse the existing arm-then-confirm flow (TR-26)
// rather than inventing a second confirmation pattern.
struct Sidebar: View {
    let ladder: [LadderLevel]
    let lastPrice: Decimal?
    let budget: Decimal
    let startingBudget: Decimal
    @Binding var qty: Int
    @Binding var bracket: BracketSettings
    var onBuy: () -> Void
    var onSell: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BudgetHeader(budget: budget, startingBudget: startingBudget)
            QuickExecutionTicket(lastPrice: lastPrice, qty: $qty, bracket: $bracket, onBuy: onBuy, onSell: onSell)
            Divider().background(Theme.borderSubtle)
            LadderView(ladder: ladder)
        }
        .frame(width: 220)
        .background(Theme.bgSurface)
        .overlay(Rectangle().fill(Theme.borderSubtle).frame(width: 1), alignment: .leading)
    }
}

// TR-41 minimal scope: account balance, colored relative to the starting balance (not
// zero) so it reads as "up/down for this session" rather than an absolute good/bad value.
// The digit-roll comes from .numericText — ContentView wraps the mutation in
// withAnimation, so this just needs to declare the transition.
private struct BudgetHeader: View {
    let budget: Decimal
    let startingBudget: Decimal

    private var color: Color {
        if budget > startingBudget { return Theme.bull }
        if budget < startingBudget { return Theme.bear }
        return Theme.textPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BUDGET").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text("\(budgetString) EUR")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(truncating: budget as NSNumber)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.bgElevated)
        .overlay(Rectangle().fill(Theme.borderSubtle).frame(height: 1), alignment: .bottom)
    }

    private var budgetString: String {
        budget.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private struct QuickExecutionTicket: View {
    let lastPrice: Decimal?
    @Binding var qty: Int
    @Binding var bracket: BracketSettings
    var onBuy: () -> Void
    var onSell: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ORDER TICKET")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Button(action: onSell) {
                    VStack(spacing: 2) {
                        Text("SELL").font(.system(size: 12, weight: .bold))
                        Text(lastPrice.map(priceString) ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Theme.bear.opacity(0.18))
                .foregroundStyle(Theme.bear)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.bear.opacity(0.5), lineWidth: 1))

                Button(action: onBuy) {
                    VStack(spacing: 2) {
                        Text("BUY").font(.system(size: 12, weight: .bold))
                        Text(lastPrice.map(priceString) ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Theme.bull.opacity(0.18))
                .foregroundStyle(Theme.bull)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.bull.opacity(0.5), lineWidth: 1))
            }

            HStack {
                Text("Qty").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Stepper(value: $qty, in: 1...100) {
                    Text("\(qty)").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                }
                .labelsHidden()
                Text("\(qty)").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.textPrimary)
            }

            Divider().background(Theme.borderSubtle)
            Text("BRACKET (price distance)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            BracketRow(label: "SL", enabled: $bracket.slEnabled, distance: $bracket.slDistance)
            BracketRow(label: "TP", enabled: $bracket.tpEnabled, distance: $bracket.tpDistance)
            BracketRow(label: "TSL", enabled: $bracket.tslEnabled, distance: $bracket.tslDistance)
            BracketRow(label: "BE at", enabled: $bracket.beEnabled, distance: $bracket.beTrigger)
        }
        .padding(12)
    }

    private func priceString(_ p: Decimal) -> String {
        p.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private struct BracketRow: View {
    let label: String
    @Binding var enabled: Bool
    @Binding var distance: Decimal

    var body: some View {
        HStack {
            Toggle(isOn: $enabled) {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.checkbox)
            .frame(width: 70, alignment: .leading)
            Spacer()
            TextField("", value: $distance, format: .number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .disabled(!enabled)
        }
    }
}

private struct LadderView: View {
    let ladder: [LadderLevel]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LADDER — MOCK DATA")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            HStack {
                Text("Bid").frame(maxWidth: .infinity, alignment: .leading)
                Text("Price").frame(maxWidth: .infinity, alignment: .center)
                Text("Ask").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12).padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ladder) { row in
                        LadderRowView(row: row)
                    }
                }
            }
        }
    }
}

private struct LadderRowView: View {
    let row: LadderLevel
    private let maxSize: CGFloat = 400

    var body: some View {
        HStack(spacing: 0) {
            sizeCell(row.bidSize, color: Theme.bear, alignment: .leading)
            Text(priceString(row.price))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
            sizeCell(row.askSize, color: Theme.bull, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        // VD-02/VD-03: ladder numerics read at 13-14pt, rows 22-28pt — the old 20pt row
        // with 10pt digits was the "numbers too small to read" complaint.
        .frame(height: 26)
    }

    private func sizeCell(_ size: Int, color: Color, alignment: Alignment) -> some View {
        ZStack(alignment: alignment == .leading ? .trailing : .leading) {
            if size > 0 {
                Rectangle()
                    .fill(color.opacity(0.2))
                    .frame(width: min(CGFloat(size) / maxSize, 1) * 70)
            }
            Text(size > 0 ? "\(size)" : "")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func priceString(_ p: Decimal) -> String {
        p.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}
