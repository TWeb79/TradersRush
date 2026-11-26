# SetupRush Trader — Feature Review & Backlog

Reviewed against: `SETUPRUSH_TRADER_PROJECT_SPEC.md` (v1.1, 912 lines) and the CX
transformation brief given in-session. Snapshot as of 2026-11-26, 9 files / ~860 lines.

## What exists today

- **Chart**: candlestick rendering, pinch-to-zoom anchored at the pinch point, horizontal
  pan, last-price tag (locale-fixed). No line overlay, no other chart types, no axes.
- **Footprint** (best-covered feature): compact + zoomed-in numeric tiers, Bid×Ask / Delta
  mode switch that now actually differs at every zoom level, built on the DeltaTrader
  playbook's causal bid/ask-split construction.
- **Order entry**: ticket with BUY/SELL (mock price), qty stepper; synthetic DOM ladder
  with heat bars, clearly labeled "MOCK DATA".
- **Execution gestures**: keyboard B/S + Return/click confirm banner (spec CH-25a), plus a
  trackpad two-finger pull-to-arm gesture (ring, center knob that blends grey→color at 80%
  pull, directional arrow) that exceeds what the spec asked for here.
- **Positions/Orders dock**: tabs with honest empty states — never fabricates fake open
  positions (only the price/ladder feed is mock-labeled synthetic data).
- **Design system**: tokens from the CX brief's §4 palette, tabular/monospaced numerics,
  restrained motion (Reduce Motion respected on the gesture overlay).
- **Packaging**: real `.app` bundle + generated icon, launchable from the Dock.

Everything above runs against `MockTradingGateway` — there is no real `TradingGateway`/MCP
client. That's the single root blocker behind most of what's below.

## In-flight (requested, not yet built)

1. **SL distance / TSL / TP / BE fields** on the order ticket.
2. **Simulated position lifecycle** — a live mock price tick loop so SL/TP/TSL/BE can
   actually trigger and close a position (currently `submit()` only prints; positions never
   open or close).
3. **Floating ±€ close alert** ("+400 EUR" in green / "-400 EUR" in red, game-style pop +
   fade) on position close.

## Gaps vs. the product spec

### Chart (§7.1) — partial
- No line overlay (CH-01 requires candlestick **+** line simultaneously, dual representation)
- No Hollow/Heikin-Ashi/OHLC-bar/Line/Area chart types (CH-02) — candlestick only
- **No P&L badges pinned to the chart** (CH-10–19a) — the spec's signature feature; blocked
  on positions actually existing (see in-flight #2 above, which unblocks this)
- No price axis / time axis (CH-05) — only the single last-price tag exists
- No crosshair / HUD / OHLC tooltip (CH-20–23)
- No session-gap collapsing (CH-08), no multiple timeframes or TF switcher (CH-27), no
  lazy history loading (CH-28)
- No drawing tools (CH-30–33, P2 in spec too — lowest priority)

### Subplot oscillators (§7.2) — not started
No subplot pane, no RSI/MACD/Volume/ATR/etc., no indicator settings sheet.

### Order book / Level 2 (§7.3) — partial
- Ladder has no auto-center/re-center, no best-bid/ask highlight, no spread display, no
  large-lot highlighting, no Time & Sales tape, no own-order markers, no imbalance gauge,
  no ladder-click trading (OB-02–11)
- Ticket is missing: order-type switcher (MKT/LMT/STP/STP-LMT), price field, **bracket
  toggle** (the in-flight SL/TP/TSL/BE work *is* this), TIF selector, reduce-only toggle,
  Flatten/Cancel-All, order summary line, execution feedback states, idempotency key
  (OB-20–24)

### Depth visualizer (§7.4) — not started
No cumulative bid/ask depth curve, wall detection, or imbalance gauge at all.

### Header & system controls (§7.5) — minimal
- No symbol search, layout picker, or multi-instrument tabs
- No connection/status badge cluster (Link/Ping, Data feed, Account sync, Server env
  LIVE/DEMO, Market session) — the "MOCK DATA" badge is honest but is not this
- No workspace presets

### Trading & risk (§10) — minimal
- No real order types (everything is an instant mock fill), no TIF
- **No RiskGuard**: no max order size, daily loss lock, margin check, fat-finger checks,
  kill switch, confirmation-policy matrix (TR-20–28)
- No order lifecycle state machine (Draft→Validating→...→Filled/Rejected)
- No manual position actions (Close, Close ½, Reverse, Add-to-position) — will become
  relevant once positions actually open (in-flight #2)
- No aggregated account P&L/equity/margin display (TR-40–41)

### Security (§11) — not started
No TLS/auth, no Keychain, no app lock, no least-privilege read-only mode, no
prompt-injection/untrusted-data handling. **Not applicable until a real gateway exists**,
but must land before ever pointing this at a live account — do not skip.

### Everything else in the spec — not started
Settings screen (§13), error-handling UI matrix (§14), compliance/risk-disclosure screens
(§15), diagnostics/observability (§12.5), alerts (§10.7), trade journal (§10.8).

## Gaps vs. the CX transformation brief

- **Global command bar**: only title + mock-data badge + footprint toggle exist; no
  instrument/account/session selectors, no search, no settings entry
- **Account & risk strip**: not built — no P&L/exposure/margin/drawdown visibility
- **Workspace customization**: no resizable/collapsible panels, no saved layouts, no
  fullscreen chart mode, no compact/balanced/focus density modes
- **Responsive/multi-device**: desktop-only; no tablet/mobile layout work
- **Trading lifecycle**: no watchlists, no trade journal, no performance analytics,
  no pre-trade prep surfaces
- **Accessibility**: partial — Reduce Motion is respected on the gesture overlay, but no
  VoiceOver label audit, no formal WCAG contrast check, no keyboard focus-ring audit

## Prioritized backlog

**P0 — finish in-flight, no backend needed**
1. SL / TSL / TP / BE ticket fields + simulated tick loop + position open/close
2. ±€ close alert
3. Manual position actions in the dock (Close, Close ½, Reverse) — trivial once #1 lands
4. P&L badges pinned to the chart at entry price (CH-10–19a) — now demoable once positions
   are real
5. Price/time axes on the chart (CH-05) — basic legibility gap
6. Crosshair + OHLC/indicator HUD (CH-20–23)

**P1 — still mock-data-friendly**
7. Line overlay + additional chart types (CH-01/02)
8. Oscillator subplot: start with Volume + RSI (§7.2)
9. Depth visualizer cumulative curve (§7.4)
10. Header status badge cluster (Link/Data feed/Account sync/Server env/Market session) —
    even static/mock values give the right information architecture
11. Settings screen skeleton (Connection, Trading defaults, Appearance)
12. RiskGuard basics: max order size, large-order confirm, Flatten/Cancel-All

**P2 — needs a real backend to do honestly**
13. **Real `TradingGateway`/MCP client** against the actual cTrader MCP server (Appendix A
    contract) — the actual foundational blocker for nearly everything else
14. Auth/Keychain, connection state machine, reconnect/backoff, link telemetry
15. Persistence (candle cache, workspace layout) via SwiftData/GRDB
16. Security requirements (§11) — mandatory before any live-account connection
17. Real order lifecycle state machine, idempotency keys, timeout reconciliation
18. Compliance/risk-disclosure screens, audit log

**P3 — deferred (P2 in the spec itself)**
19. Drawing tools, price/P&L alerts, trade journal, multi-instrument tabs, workspace
    presets, iPad/iPhone phase 2, multi-monitor, popped-out windows

## Open questions (spec §20, still unanswered)

The spec's own open-questions list is still live: exact MCP tool contract, true Level 2
availability, hedging vs. netting account mode, distribution target, P&L unit preference,
push-alert requirement, iPhone-at-v1 or not, MCP remote-access method, regulatory
jurisdiction. Nothing past P0/P1 above can be built for real without these answers.
