# Project Specification: SetupRush Trader — Native macOS Futures Trading Client for cTrader MCP

| Field | Value |
|---|---|
| Document type | Product, UX/CX and Trading Requirements Specification |
| Status | Draft v1.1 — pivoted macOS-first 2026-11-26 (was iPad-first v1.0) |
| Date | 2026-11-26 |
| Target platforms | macOS 14+ (Sonoma), Apple Silicon + Intel (primary); iPadOS/iOS 17+ (Phase 2, deferred) |
| Language / UI | Swift 5.10+/6, SwiftUI + AppKit interop (+ Metal for chart rendering) |
| Backend | User's own cTrader MCP server (Model Context Protocol) |
| Reference product | Professional futures trading UI on setuprush.com (originally iPad layout, adapted for desktop) |

---

## 0. How to Read This Document

- **MUST / SHOULD / MAY** follow RFC 2119 meaning.
- Requirement IDs (e.g. `CH-04`, `TR-12`) are stable and meant to be used in tickets and test cases.
- Items marked **[ASSUMPTION]** are inferred from the reference description and must be validated.
- Items marked **[OPEN]** are decisions required from the product owner (see §20).

---

## 1. Vision & Product Summary

### 1.1 Vision
A touch-first, low-latency, professional-grade futures trading terminal for iPad (and a condensed iPhone version) that turns the user's **cTrader MCP server** into a fully interactive trading cockpit: live chart, Level 2 depth, one-tap execution, and position health visible *on the chart itself*.

### 1.2 What we are building
A **native Swift application** that:
1. Connects to the user's cTrader MCP server as an **MCP client** (authenticated, encrypted, auto-reconnecting).
2. Streams market data (quotes, trades, depth) and account/position/order state.
3. Renders a multi-pane, gesture-driven workspace: price chart, oscillator subplot, order book, depth visualizer, order ticket, status header.
4. Sends and manages orders with strong safety rails (confirmation, validation, risk limits, idempotency).

### 1.3 Design pillars
1. **Glanceability** – position health, P&L, connection state readable in < 1 second.
2. **Speed** – ≤ 2 taps from intent to order submitted; sub-frame chart interaction.
3. **Trust** – never show stale data as live; never silently fail an order.
4. **Density without clutter** – institutional-grade information density, tablet-optimized touch targets.
5. **Resilience** – graceful behavior on flaky mobile networks, backgrounding and device rotation.

### 1.4 Non-goals (v1)
- No strategy backtesting or algo/cBot authoring.
- No social/copy trading.
- No on-device brokerage account creation / KYC / funding.
- No Android or watchOS. **iPadOS/iOS are Phase 2** (deferred, not dropped) — the domain/application layer and `TradingGateway` abstraction are shared; only the Presentation layer and input handling differ per platform.
- No custom drawing-tool suite beyond a minimal set (see CH-30..CH-33).
- The app is **not** a broker; it is a client to the user's own MCP infrastructure.

### 1.5 Platform pivot note (v1.1)
This spec originally targeted iPadOS/iOS first (touch-first). As of v1.1 it targets **macOS first**: a resizable desktop window instead of a fixed tablet layout, mouse + trackpad as equally first-class input (not a touch fallback), and a full menu bar mirroring every keyboard shortcut. Touch-specific requirements (Apple Pencil, haptics beyond basic feedback, Face ID, Live Activities, Widgets) are removed from v1 scope; where the original requirement was gesture-based, §7.1.3/7.1.4 below define the pointer/trackpad equivalent. Sections unrelated to input/platform (System Architecture §6, Order Book §7.3, Depth §7.4, Trading §9, MCP contract Appendix A) are unaffected by the pivot and carry over unchanged.

---

## 2. Assumptions, Dependencies & Constraints

### 2.1 cTrader MCP dependency [ASSUMPTION]
The user's cTrader MCP server exposes tools/resources wrapping the **cTrader Open API** (protobuf, `OpenApiMessages`) such as: account info, symbol list/details, trendbars (historical OHLC), live spot subscription, depth-of-market subscription, positions, pending orders, order create/amend/cancel, position close/amend.

The exact tool names, schemas and transport are **not yet known**. This spec therefore defines:
- an **abstraction layer** (`TradingGateway` protocol, §6.3) so the UI is independent of the wire format;
- a **proposed MCP tool contract** (Appendix A) that the server should satisfy, or that an adapter in the app maps onto the real tool names.

### 2.2 Transport
- **Both transports are supported** on macOS (unlike the original iOS-only plan): MCP over **Streamable HTTP/SSE** for a remote server (the user's actual deployment — see §2.2a), and **stdio** (local subprocess) for a locally-running MCP server. `TradingGateway` is transport-agnostic; a `TransportConfig` (http(url, auth) | stdio(command, args)) picked in Connection Setup selects the concrete `MCPClient` implementation.
- HTTP/SSE: must be reachable from the Mac: public HTTPS endpoint, VPN (WireGuard/Tailscale), or Cloudflare Tunnel. **The app MUST NOT require disabling App Transport Security.**
- Real-time push (ticks/depth/fills) arrives as MCP **notifications / resource subscriptions** or SSE events. If the server only offers request/response, the app falls back to **adaptive polling** (see §6.5) with a visible "Delayed/Polling" badge.

### 2.2a Deployment reality [confirmed]
The user's actual cTrader MCP server runs **remotely** (not as a local subprocess on the Mac running this app), so **HTTP/SSE is the transport that matters in practice**; stdio support is built for completeness/local-dev convenience but isn't the deployment path. Exact host/port are **not yet provided** — Connection Setup (§5) MUST accept a user-entered host/port/path at runtime; nothing is hardcoded. (A LAN probe of a candidate host during spec work found no MCP endpoint listening yet — this is expected pre-deployment, not a bug.)

### 2.3 Market data constraints [ASSUMPTION]
- True Level 2 / DOM for **futures** depends on the broker/cTrader feed. If the feed provides only top-of-book, the depth UI MUST degrade gracefully (show "Level 1 only").
- The reference UI shows P&L values like `+8343`, `-342` — presumably in account currency, ticks or points. The unit MUST be user-selectable (§9.4, TR-40).

### 2.4 Regulatory & store constraints
- The app is a trading client; for private/personal use on macOS, **direct distribution outside the Mac App Store** (Developer ID signed + notarized `.app`/DMG) is the recommended v1 path — it avoids App Review's financial-app review entirely and is simpler than the iOS TestFlight/Ad Hoc path the original spec needed. Mac App Store distribution is not a v1 goal.
- Include required **risk disclosure** and **"not financial advice"** screens.

### 2.5 Development constraints
- Building and signing require **macOS + Xcode + Apple Developer account** (for notarization/Developer ID; not required to run unsigned locally during development). Native to this environment — no cross-compilation concern.

---

## 3. Users & Personas

| Persona | Description | Key needs |
|---|---|---|
| **Active Futures Day Trader (primary)** | Trades index/commodity futures intraday from an iPad on a desk stand | Speed, DOM, one-tap orders, on-chart P&L |
| **Swing/Position Monitor** | Checks positions during the day, occasionally adjusts SL/TP | Clear risk overview, push alerts, safe edits |
| **Remote Operator / System Owner** | Owns the MCP server, wants a mobile cockpit | Connection diagnostics, kill-switch, audit log |

**Context of use:** landscape iPad (10.9"–13"), often on Wi-Fi, sometimes cellular; sessions of minutes to hours; high-stress moments where mis-taps are costly.

---

## 4. Platform & Device Strategy

### 4.1 Form factors
| Window | Layout | Priority |
|---|---|---|
| Main window, resizable (min ~1280×800) | Full 4-zone workspace (§8.1), `HSplitView`/`VSplitView` instead of fixed percentages | **P0** |
| Depth Visualizer, popped out | Own `NSWindow`, same shared state as docked pane | P0 |
| Order Book, popped out | Own `NSWindow`, same shared state as docked pane | P1 |
| Multiple Workspace windows (different symbols) | P2 — not required for v1 | P2 |

iPadOS/iOS form factors (iPad landscape/portrait, Split View, iPhone) are **Phase 2** — the original table's requirements are preserved as-is for that phase, not deleted; see §1.5.

### 4.2 OS capabilities used
Dynamic Type, Dark Mode (default), mouse + trackpad (both first-class — two-finger trackpad gestures and mouse scroll/click-drag are equivalent input paths, see §7.1.4), full menu bar mirroring every keyboard shortcut, Touch ID/password unlock (replaces Face ID), Keychain, Background App Refresh N/A (desktop app runs continuously while open), Push Notifications (via server relay, optional).

Removed from v1 (touch/mobile-only, not applicable to macOS): Apple Pencil, Haptics, Face ID, Live Activities, Widgets. These remain in scope for the Phase 2 iPad/iPhone build.

---

## 5. Information Architecture

```
App
├── Onboarding & Connection Setup
│     ├── Add MCP Server (URL, auth)
│     ├── Select cTrader account (Live / Demo)
│     └── Risk disclosure + biometric lock setup
├── Workspace (main)
│     ├── Header Bar
│     ├── Chart Zone (price + indicators subplot)
│     ├── Order Book / DOM + Quick Order Panel (sidebar)
│     ├── Depth Visualizer
│     └── Positions / Orders / History dock
├── Symbol Search & Watchlist (sheet)
├── Timeframe & Chart Type (popover)
├── Indicators & Layout Manager (sheet)
├── Alerts (P2)
├── Account & Risk Dashboard
├── Settings
│     ├── Connection & Servers
│     ├── Trading Defaults & Safety
│     ├── Appearance & Layout
│     ├── Units & Formats
│     ├── Notifications
│     └── Diagnostics & Logs
└── About / Legal / Risk Disclosure
```

---

## 6. System Architecture

### 6.1 High-level diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                        SwiftUI Presentation                        │
│  WorkspaceView │ ChartView │ BookView │ DepthView │ TicketView ...  │
└───────────────▲────────────────────────────────────────────────────┘
                │ (Observation / @Observable ViewModels, async streams)
┌───────────────┴────────────────────────────────────────────────────┐
│                       Domain / Application Layer                   │
│  MarketDataStore │ OrderBookStore │ PortfolioStore │ OrderManager    │
│  RiskGuard │ AlertEngine │ IndicatorEngine │ SessionManager          │
└───────────────▲────────────────────────────────────────────────────┘
                │ protocol TradingGateway / MarketDataGateway
┌───────────────┴────────────────────────────────────────────────────┐
│                          Data Layer                                │
│  MCPClient (JSON-RPC 2.0) │ Transport (Streamable HTTP/SSE)          │
│  Reconnect/Backoff │ Codec (JSON ⇄ domain) │ Cache (SwiftData/GRDB)  │
│  Keychain │ Logger                                                    │
└───────────────▲────────────────────────────────────────────────────┘
                │ HTTPS (TLS 1.3) / VPN
        ┌───────┴────────┐
        │ cTrader MCP    │──► cTrader Open API ──► Broker / Exchange
        └────────────────┘
```

### 6.2 Technology choices
| Concern | Choice | Rationale |
|---|---|---|
| UI | SwiftUI + `Observation` framework | Modern, declarative, adaptive |
| Chart rendering | **Custom Metal / Core Graphics layer** wrapped in `UIViewRepresentable`; Swift Charts only for non-realtime widgets | Swift Charts cannot sustain 60–120 fps with thousands of candles + crosshair + overlays |
| Concurrency | Swift Concurrency (`actor`, `AsyncStream`), strict concurrency on | Safe real-time data flow |
| MCP client | Official MCP Swift SDK if mature; otherwise a thin in-house JSON-RPC 2.0 client | Control over streaming/notifications |
| Persistence | SwiftData or GRDB (SQLite) | Candle cache, layouts, journal |
| Secrets | Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) + Secure Enclave-gated access control | Credential safety |
| Networking | `URLSession` with `URLSessionWebSocketTask`/SSE parser | Native, ATS-compliant |
| DI | Lightweight protocol-based container | Testability |
| Logging | `os.Logger` + redacted structured logs | Privacy |
| Testing | XCTest, Swift Testing, snapshot tests, MCP mock server | See §17 |

### 6.3 Core abstractions (protocol sketch)

```swift
protocol TradingGateway: Sendable {
    // Session
    func connect() async throws
    func disconnect() async
    var connectionState: AsyncStream<ConnectionState> { get }
    var telemetry: AsyncStream<LinkTelemetry> { get }          // ping, jitter, feed health

    // Reference data
    func symbols() async throws -> [InstrumentSpec]
    func spec(for id: InstrumentID) async throws -> InstrumentSpec

    // Market data
    func history(_ id: InstrumentID, tf: Timeframe, range: DateInterval) async throws -> [Candle]
    func quotes(_ id: InstrumentID) -> AsyncStream<Quote>
    func trades(_ id: InstrumentID) -> AsyncStream<Trade>       // time & sales (if available)
    func depth(_ id: InstrumentID) -> AsyncStream<DepthUpdate>  // snapshot + deltas

    // Account
    func account() async throws -> AccountSnapshot
    func accountUpdates() -> AsyncStream<AccountUpdate>
    func positions() async throws -> [Position]
    func orders() async throws -> [WorkingOrder]
    func executions(since: Date) async throws -> [Execution]

    // Trading
    func place(_ request: OrderRequest) async throws -> OrderAck
    func amend(_ amend: AmendRequest) async throws -> OrderAck
    func cancel(_ id: OrderID) async throws
    func close(_ id: PositionID, volume: Decimal?) async throws -> OrderAck
    func flatten(scope: FlattenScope) async throws -> [OrderAck]
}
```

All monetary/price values use **`Decimal`** (never `Double`) and are normalized to instrument **tick size**.

### 6.4 Data models (key entities)
- `InstrumentSpec`: id, symbol, description, exchange, currency, **tickSize, tickValue, pointValue/contractMultiplier**, lotSize/min/max/step volume, expiry, tradingSessions, marginPerContract, digits, supportsDepth.
- `Candle`: time (UTC), o, h, l, c, volume, tickVolume, isClosed.
- `Quote`: bid, ask, bidSize, askSize, last, time.
- `DepthLevel`: price, size, side, orderCount?; `DepthUpdate`: snapshot | delta(add/modify/remove), sequence, timestamp.
- `Position`: id, instrument, side, volume, avgPrice, openTime, SL, TP, swap/commission, **unrealizedPnL (derived locally from live quote)**, realizedPnL.
- `WorkingOrder`: id, type, side, volume, limitPrice, stopPrice, TIF, SL/TP, state, createdAt, label/clientOrderId.
- `Execution`: fill id, order id, price, volume, time, fees.
- `Trade` (time & sales / footprint input): price, qty, side (buy | sell | unknown), time, sequence.
- `FootprintBar` (derived, client-side aggregation — see CH-34): bar time, `priceBins: [PriceBin]` where `PriceBin` = price, bidVolume, askVolume, delta (= askVolume − bidVolume); `poc` (price bin with max total volume in this bar).
- `AccountSnapshot`: balance, equity, margin used, free margin, margin level, daily P&L, currency.
- `LinkTelemetry`: rttMs (p50/p95), feedLagMs, lastTickAge, reconnectCount, serverTimeSkew.

### 6.5 Real-time data pipeline
1. **Subscribe** to quotes + depth + account events for the active instrument(s) via MCP notifications/resource subscriptions.
2. **Coalesce**: incoming ticks processed on a dedicated actor; UI is fed by a **display-link-paced** snapshot (max 60/120 Hz) — never one UI update per tick.
3. **Sequence integrity**: depth deltas carry sequence numbers; on gap → request fresh snapshot and mark book as "Resyncing".
4. **Candle building**: last candle updated from ticks; closed candles reconciled with server trendbars on candle rollover.
5. **Fallback polling** (if push unavailable): adaptive 250 ms–2 s interval; badge "POLLING".
6. **Clock sync**: estimate server-time offset to keep crosshair timestamps and candle boundaries correct.
7. **Staleness**: if `now - lastTick > threshold` (default 3 s, configurable) → data is flagged **STALE**, order buttons enter a cautious state (TR-31).

### 6.6 Connection state machine

```
 Disconnected ─connect()─► Connecting ─ok─► Authenticating ─ok─► Syncing ─ok─► Live
      ▲                       │fail            │fail               │fail         │ drop
      │                       ▼                ▼                   ▼             ▼
      └──── Failed(reason) ◄──┴────────────────┴───────────────────┴──── Reconnecting(backoff)
```
- Exponential backoff with jitter (0.5 s → 30 s cap), reset on success.
- On `Live` after reconnect: **re-subscribe, re-snapshot positions/orders/depth, reconcile** any state changes during outage and present a "Reconnected — N changes" toast.
- App foreground → immediate health probe; app background → graceful pause of streams after grace period (default 30 s) and **no order actions possible**.

---

## 7. Feature Specifications

### 7.1 Interactive Multi-Tier Price Chart (`CH-*`)

**Purpose:** Primary analysis + situational awareness surface.

#### 7.1.1 Rendering
- **CH-01** The chart MUST render **Japanese candlesticks** and a **continuous line/curve overlay** simultaneously (dual representation). Line source default = close; options: close, HL2, HLC3, VWAP, SMA/EMA of close. Line style: smooth (monotone cubic interpolation), 1.5–2 pt, user-selectable colour.
- **CH-02** Chart types: Candlestick+Line (default), Candlestick, Hollow candles, Heikin-Ashi, OHLC bars, Line, Area. (Renko/Range/Tick charts: P2.)
- **CH-03** Rendering target: **≥ 60 fps** during pan/zoom with ≥ 5,000 visible+buffered candles on iPad (≥ 120 fps on ProMotion where feasible). Zero main-thread layout work during gestures.
- **CH-04** Candle colouring uses the global palette (§9.2); wick/body proportions pixel-snapped for crisp rendering on Retina.
- **CH-05** Right-hand price axis with adaptive tick spacing aligned to the instrument **tick size**; bottom time axis with adaptive labels (session-aware, timezone-selectable: UTC / exchange / local).
- **CH-06** **Last price line + tag** (colour by tick direction), **bid/ask lines** (optional), previous close, session high/low (optional), countdown to candle close (optional).
- **CH-07** Live candle updates animate smoothly (no flicker); closed-candle rollover is seamless.
- **CH-08** Session breaks, weekends and holidays are collapsed (no empty gaps) for futures; contract-roll markers on continuous charts [OPEN: continuous-contract support depends on MCP].

#### 7.1.2 Live Floating P&L Badges (signature feature)
- **CH-10** For each open position, a **badge MUST be pinned to the chart at the y-coordinate of its entry price** (and, optionally, a second marker at the *current* price) with live-updating P&L text (e.g. `+8343`, `-700`).
- **CH-11** Badge styling: green fill/text for profit, red for loss, neutral grey at breakeven (± one tick). Contrast ≥ 4.5:1. Includes a leading side glyph (▲ long / ▼ short) and size (e.g. `2×`) in compact form on tap/expand.
- **CH-12** A thin **dashed horizontal line** connects entry price across the visible time range; line extends from the entry candle to the right edge.
- **CH-13** Badges are **anchored in price-space and time-space**: they track correctly through pan, zoom and auto-scale. When the entry candle is off-screen to the left, the badge **pins to the left edge** at the correct price; when entry price is off-screen vertically, the badge **clamps to the top/bottom edge** with an arrow indicating direction and the distance.
- **CH-14** **Collision avoidance:** overlapping badges are stacked/fanned with leader lines; a cluster of ≥ 4 collapses into a single "N positions: net ±X" badge, expandable on tap.
- **CH-15** **Unit toggle** (long-press any badge or header chip): currency / ticks / points / % of equity / R-multiple (if SL defined). Selection persists.
- **CH-16** **Tap on badge** → compact **Position Card** popover: side, volume, avg price, SL, TP, P&L, time in trade, MAE/MFE (optional), buttons: *Close*, *Close ½*, *Reverse*, *Edit SL/TP*.
- **CH-17** **Drag-to-modify:** SL and TP lines (when set) render as draggable handles; dragging proposes new price (snapped to tick) with live "risk Δ / reward Δ" preview; release → confirmation sheet (or immediate, if user enabled "No-confirm modify"). Pending-order lines are draggable the same way.
- **CH-18** Pending (working) orders render as dashed lines with a label chip (`BUY LMT 2 @ 5,412.25`) and an ✕ to cancel.
- **CH-19** Realized trades (executions) optionally plotted as small entry/exit markers with connecting lines for the current session.
- **CH-19a** P&L values update on **every quote tick** (UI-coalesced) using **local mark-to-market** computed with instrument spec (tickValue × ticks × volume), reconciled against server-reported P&L at a low cadence; discrepancy > tolerance shows a subtle ⚠︎ and logs.

#### 7.1.3 Pointer Crosshair & Inspection (macOS; supersedes touch crosshair for v1)
- **CH-20** Crosshair is **live on hover** — no hold/toggle needed; a pointing device always has a free hover state, unlike touch. Vertical + horizontal lines snap to nearest candle (x) and free price (y) — optional "magnet" snapping to O/H/L/C.
- **CH-21** A **data tooltip/HUD** shows: timestamp (in selected TZ), O, H, L, C, change (abs/%), volume, and values of every visible indicator at that bar. HUD docks to the top-left and **never occludes the cursor** (flips side as needed). The y-axis shows a **price tag** at the crosshair level.
- **CH-22** Crosshair **syncs across panes** (main chart, oscillator subplot, depth ladder highlighting the corresponding price row).
- **CH-23** Crosshair **dismisses** when the pointer leaves the chart area. A **⇧-hover** (or two-finger click-hold on trackpad) pins a measurement tool: Δ price, Δ ticks, Δ %, Δ time, bars count.
- **CH-24** *(superseded — see §1.5; original touch/Pencil requirement preserved for Phase 2.)*

#### 7.1.4 Navigation gestures — mouse + trackpad (equally first-class)
| Action | Trackpad | Mouse |
|---|---|---|
| Pan time axis | Two-finger horizontal swipe (inertial) | Scroll wheel horizontal |
| **Arm Long** (new, see CH-25a) | Two-finger swipe **up**, anywhere on chart | `B` keyboard shortcut / BUY ticket button |
| **Arm Short** (new, see CH-25a) | Two-finger swipe **down**, anywhere on chart | `S` keyboard shortcut / SELL ticket button |
| Scale price axis manually | Click/drag on price axis gutter (disables auto-scale; "A" re-enables) | Click-drag on price axis gutter |
| Zoom time axis | Pinch (anchored at pinch centre) | ⌥ (Option) + scroll, anchored at cursor |
| Reset zoom / jump to latest | Double-tap (two-finger) | Double-click |
| Drag-to-modify SL/TP handles | Click-drag the handle | Click-drag the handle |
| Dismiss popovers/crosshair/armed trade | Click empty area | Click empty area |
| Toggle sidebar | Three-finger edge-swipe from right | Toolbar button / ⌘\\ |
| Jump to realtime edge | "⏭ Now" button; shows when scrolled away, with "N new bars" counter | same |

- **CH-25** Gestures MUST have **conflict resolution** via hit-testing priority: handles > badges > crosshair > pan.
- **CH-25a** **Arm Long/Short gesture.** Two-finger vertical swipe (anywhere on the chart, either direction) arms a trade at the ticket's current symbol/quantity. Default (one-tap execution **OFF**): shows a pulsing "ARMED LONG/SHORT — click/Return to confirm" banner with a 10 s auto-disarm, reusing the Arm-then-tap pattern (TR-33); a confirming click, Return key, or the ticket's BUY/SELL button submits it, clicking empty area or timeout disarms. If the user has enabled **One-tap execution mode** (OB-22, opt-in with explicit risk acknowledgment), the swipe **submits immediately** instead — same behavior as the ticket buttons under that mode. Either path still flows through RiskGuard, stale-feed gating, and the full confirm-policy matrix (§ Trade Execution & Safety) — this is a new *input path* into the existing safeguarded order pipeline, not a bypass of it. This gesture replaced vertical two-finger panning (moved to the axis-gutter drag above) to avoid a conflicting mapping.
- **CH-26** Provide a **"Lock chart"** mode that disables all pan/zoom (and Arm Long/Short) to prevent accidental movement while trading.

#### 7.1.5 Timeframes & history
- **CH-27** Timeframes: 1s*, 5s*, 15s*, 30s* (*if tick data/trendbar available), 1m, 2m, 3m, 5m, 10m, 15m, 30m, 1h, 2h, 4h, 1D, 1W, 1M. Quick-switch chips in the header + custom timeframe entry.
- **CH-28** **Lazy history loading:** fetch older bars when the user scrolls within 200 bars of the left edge; cache locally; show subtle "loading" shimmer at the left edge.
- **CH-29** **Cache policy:** keep last N candles per (instrument, tf) on disk; invalidate on contract roll or data corrections.

#### 7.1.7 Footprint / Delta-Volume View (new, v1.1 — from DeltaTrader playbook §11)
- **CH-34** A **chart mode** (alongside Candlestick/Line/Heikin-Ashi, CH-02) that renders each bar as **price bins** (one row per tick-sized price level within the bar's range) showing bid-volume | ask-volume | delta per bin, colored for positive/negative delta (distinct colors, visible zero line, numeric delta never color-only — accessibility, §AX). Built from `FootprintBar`, aggregated client-side from the `Trade` stream per the causal (no future data) construction in the DeltaTrader playbook §11.
- **CH-35** **Data dependency [OPEN, new Appendix A item]:** requires a `subscribe_trades(symbol)` MCP stream delivering `Trade` events (price, qty, side, sequence) — not yet in Appendix A's tool contract. If the live MCP server cannot provide aggressor-side trade data, Footprint mode **degrades gracefully** to "Volume only, no delta" (same pattern as Level 1-only depth degradation, §2.3), same as any other data-quality gate in this spec.
- **CH-36 (v1, minimal scope):** bid/ask volume + delta per bin only. **Deferred to fast-follow** (not v1): session volume profile (POC/VAH/VAL) on the chart's right edge, CVD subplot, stacked-imbalance highlighting, absorption-zone overlays — all additive once the `Trade` data pipeline exists; they do not change the architecture above.
- **CH-37 Prototype note:** since the real MCP connection/credentials are not yet available, the first build ships with a `MockTradingGateway` (synthetic candles + synthetic `Trade` events, random-walk price process) so chart rendering, gestures, and Footprint mode are all exercisable before a live server exists. This stays in the codebase as a `DEBUG`/SwiftUI-preview data source after the real gateway lands, not a throwaway.

#### 7.1.6 Minimal drawing tools (P2)
- **CH-30** Horizontal line, trend line, rectangle, fib retracement, text note. **CH-31** Persist per-instrument. **CH-32** Magnet to OHLC. **CH-33** Long-press object → context menu (color, lock, delete). *Optional: alert-from-line.*

---

### 7.2 Quantitative Subplot Oscillators (`OSC-*`)

- **OSC-01** A **secondary pane directly beneath** the main chart (default 22–28% of chart-zone height), resizable by dragging the divider; collapsible; supports **multiple stacked subpanes** (max 3 in v1).
- **OSC-02** **Time-locked**: shares the exact x-axis transform (zoom, pan, crosshair) with the main chart; **no drift** at any zoom level.
- **OSC-03** Built-in indicators (v1): **Volume (with MA)**, **RSI**, **MACD (line, signal, histogram)**, **Stochastic**, **ATR**, **CCI**, **OBV**, **Momentum/ROC**. Overlays on main pane (v1): **SMA, EMA, WMA, Bollinger Bands, VWAP, Ichimoku (P2), Supertrend (P2)**.
- **OSC-04** Reference look: **distinct colour-coded lines** (e.g., yellow and white waveforms) with a configurable palette per series; line width 1–3 pt; histogram bars coloured by sign.
- **OSC-05** **Reference levels** (e.g., RSI 30/70, Stoch 20/80) drawn as dashed lines with shaded OB/OS zones; **crossing highlights** (subtle flash/marker on the candle when entering/exiting OB/OS).
- **OSC-06** **Volume surge detection:** volume bars exceeding *k × MA(volume)* are highlighted (default k = 2) and may feed alert rules.
- **OSC-07** Indicator **settings sheet**: period, source, smoothing, colours, visibility, line style; **presets** and "reset to default".
- **OSC-08** Calculation engine runs on a **background actor**; incremental update on live bar (O(1) per tick for EMA/RSI/etc.); full recompute only on history load/settings change. Results cached per (instrument, tf, params).
- **OSC-09** Correctness: indicator outputs MUST match reference implementations (TA-Lib / cTrader built-ins) within 1e-6 over test fixtures [see §17].
- **OSC-10** Subplot y-axis: auto-scale with padding; tag showing last value; optional log scale for volume.
- **OSC-11** **Volume source note:** for futures, use real contract volume when provided; if only tick volume is available, label as "Tick Vol".

---

### 7.3 Order Book / Level 2 Sidebar (`OB-*`)

#### 7.3.1 Ladder (DOM)
- **OB-01** Right-hand sidebar (default 28–32% width on iPad landscape; resizable 22–45%; collapsible) showing a **price ladder** with columns: **Bid Size | Price | Ask Size** (+ optional: *Orders count, Cumulative size, Volume at price, Delta*).
- **OB-02** Rows aligned to **tick size**; **N levels each side** (default 15, range 5–40); **auto-centre on last price** with "re-center" button & **free-scroll** that pauses auto-centre until idle 5 s or "Centre" tapped.
- **OB-03** **Best bid/ask** rows highlighted; **spread** displayed between them (in ticks and price); **last-traded price** row marked with the trade-direction tick colour.
- **OB-04** **Size bars (heat-bars):** horizontal bar behind each size cell scaled to max visible size (or percentile-clipped to avoid outliers); intensity increases with size; **large-lot highlighting** (≥ configurable threshold or ≥ 3σ).
- **OB-05** **Colour coding (institutional palette):** **asks/sell pressure = red/pink**, **bids/buy pressure = green or blue** (user-selectable scheme: *Green/Red*, *Blue/Red*, *Colour-blind safe Blue/Orange*). Colour is **never the sole indicator** (also position left/right, and labels).
- **OB-06** **Update animation:** size changes flash (brighter on increase, dimmer on decrease) for ≤ 150 ms; price rows that disappear/appear animate without layout jumps; **no re-sorting jitter**.
- **OB-07** **Tape / Time & Sales** (collapsible beneath ladder or as tab): scrolling list of prints with time, price, size, aggressor side colour; big-print highlight; pause-on-touch.
- **OB-08** **Own-order markers:** user's working orders shown in-ladder as chips at their price level (qty + side); tap to modify/cancel; drag chip to another price level to re-price (with confirm per settings).
- **OB-09** **Position marker:** entry price row tagged with avg price & live P&L.
- **OB-10** Imbalance indicator: top-of-book bid/ask size ratio bar; cumulative imbalance over N levels.
- **OB-11** **Ladder trading (P1):** tap on a bid-side price cell → place **limit buy** at that price using the active ticket quantity; tap on ask-side → **limit sell**; modifier modes: *Single-tap* (confirm per setting) vs *Arm-then-tap* (see TR-33). Prevent accidental taps with a 250 ms debounce and size-confirm haptic/visual flash.

#### 7.3.2 Quick-Execution Action Panel
Placed **directly above the ladder** (or integrated at the top of the sidebar) so thumbs reach it with minimal travel.

- **OB-20** Controls (left → right, top → bottom):
  1. **Instrument chip** (symbol + expiry), tap = symbol search.
  2. **Side toggle / big buttons:** **SELL @ bid** (red) and **BUY @ ask** (green/blue), each showing the live price and size.
  3. **Order type switcher** (segmented): **MKT | LMT | STP | STP-LMT** (+ **TRAIL** P1).
  4. **Quantity selector:** stepper (− / +), tap-to-type numeric keypad, **preset chips** (e.g. 1, 2, 5, 10, user-defined), **"% risk" mode** (sizes from SL distance, see TR-20), and *max-size lock*.
  5. **Price field** (for LMT/STP): stepper in ticks, **"Join bid / Join ask / Mid"** quick-fills, tap chart/ladder to pick.
  6. **Bracket toggle:** SL and TP in ticks/price/R-multiple/% with live risk-reward ribbon.
  7. **TIF selector:** Day / GTC / IOC / FOK / GTD (as supported).
  8. **Reduce-only / Close-only** toggle (P1).
  9. **Flatten ⏻** (close all in this instrument) and **Cancel All ✕** (working orders), both **long-press 600 ms** or double-confirm.
- **OB-21** **Order summary line:** "BUY 2 MKT ES Dec‑26 ≈ 5,412.50 · risk $750 · margin $26,400" updated live.
- **OB-22** **One-tap execution mode:** user-enabled; BUY/SELL fire immediately using current ticket (subject to RiskGuard). Default **OFF** with explicit risk acknowledgement on enabling.
- **OB-23** Execution feedback: button transitions *Idle → Sending (spinner) → Working/Filled (check) → Idle*; **fill toast** with price/size/slippage; **reject** shows reason in plain language with retry action.
- **OB-24** **Prevent double submit:** button disabled during in-flight request; **idempotency key** (`clientOrderId`) attached to every order.

---

### 7.4 Bid Depth vs Ask Depth Visualizer (`DV-*`)

- **DV-01** Lower-right quadrant panel (below ladder or as sibling) rendering the **cumulative depth curve**: x = price, y = cumulative resting size; **bids (blue)** on the left of mid, **asks (pink/red)** on the right, meeting at the **mid/spread** line.
- **DV-02** **Glow/gradient fill** under curves (low-opacity area) with **bright stroke**; the **intersection zone** near mid is visually emphasized (glow) — "market pressure at a glance".
- **DV-03** **Wall detection:** price levels where cumulative or single-level size exceeds threshold (percentile or σ-based) are **annotated** with a marker + size label ("Wall 1,250 @ 5,420.00"); tap to jump chart to that price / draw a horizontal line.
- **DV-04** **Range control:** depth window ± X ticks / ± X % (pinch to zoom horizontally); default auto-fit to N levels used in ladder.
- **DV-05** **Imbalance gauge:** bid/ask cumulative ratio within the window (e.g., 62% / 38%), colour-tinted.
- **DV-06** **Interactions:** touch-drag shows a **vertical guide** with cumulative size to that price, "distance from mid" (ticks, %), and **estimated slippage for the current ticket size** (walks the book) — "BUY 10 → avg 5,412.75 (+1.25 ticks)".
- **DV-07** Smoothly animated updates (≤ 10 fps data-driven redraw is sufficient; interpolate for visual smoothness); **no flicker on resync**.
- **DV-08** Shows **"Level 1 only / Depth unavailable"** placeholder if feed lacks depth, with explanation link.

---

### 7.5 Workspace Header & System Controls (`HD-*`)

- **HD-01** **Header bar** (height 52–60 pt iPad) with: 
  - **Left:** App menu / **Layout** icon (workspace presets), **Symbol search 🔍** (symbol + description + expiry; supports recents/favourites), **instrument chip** with live **last price, change, %** and contract expiry countdown.
  - **Centre:** **Timeframe switcher** (chips: 1m 5m 15m 1h 4h 1D + "more"), **Chart type**, **Indicators (fx)**, **Drawing tools** (P2), **Crosshair/Lock** toggles.
  - **Right:** **Connection & Status Telemetry cluster**, **Account chip** (equity, day P&L, margin level), **Alerts 🔔** (P2), **Settings ⚙︎**.
- **HD-02** **Connection/Status badges** (always visible; each tap opens a diagnostics popover):
  | Badge | States | Notes |
  |---|---|---|
  | **Link / Ping** | `● 23 ms` green < 80, amber 80–250, red > 250 / offline | RTT p50 with sparkline in popover; jitter & packet loss |
  | **Data feed** | `LIVE` / `DELAYED` / `STALE` / `POLLING` / `RESYNCING` | Age of last tick shown on STALE |
  | **Account sync** | `SYNCED` / `SYNCING` / `OUT OF SYNC` | Last reconciliation time; manual "Resync" |
  | **Server / env** | `LIVE ACCOUNT` (red outline) / `DEMO` (blue) | **Unmistakable** live-vs-demo distinction (OB, header tint) |
  | **Market session** | `OPEN` / `PRE` / `CLOSED` / `HALT` + countdown | From instrument spec + server events |
- **HD-03** **State semantics:** if Link = offline or Data = STALE → header shows a **persistent banner** ("Data stale — trading disabled" or "Offline — orders will not be sent") and trading controls transition per TR-31.
- **HD-04** **Layout customization:** save/load **workspace presets** (panel sizes, which panes visible, indicator sets, colour scheme). Cloud sync via iCloud (P2).
- **HD-05** **Symbol search:** instant filter (symbol, name, exchange), recents, favourites ★, watchlists (P1) with live mini-quotes; supports **contract month selection** (front, next, specific) and **"Front month" auto-roll** setting.
- **HD-06** **Settings access** is available but **destructive/safety settings require biometric re-auth**.
- **HD-07** **Multi-instrument (P1):** up to 2 chart tabs/instruments (iPad) with linked or independent crosshair/timeframe; **P2:** multi-chart grid.

---

## 8. Layout & Interaction Design

### 8.1 iPad landscape reference layout (P0)

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ ☰ Layout │ 🔍 ES Dec-26  5,412.50 ▲+0.8% │ 1m 5m 15m 1h 4h 1D │ fx ✎ ⊕ 🔒 │ ●23ms LIVE SYNCED DEMO ⚙ │  Header (HD)
├──────────────────────────────────────────────────────────┬───────────────────────┤
│                                                          │  [ SELL 5412.25 ][ BUY 5412.50 ]
│    PRICE CHART  (candles + line overlay)                 │  MKT|LMT|STP   Qty [−] 2 [+]  │ Quick Exec (OB-20)
│                           [+546]◄ P&L badge              │  SL [  ] TP [  ]  TIF  ⏻ ✕     │
│        [-342]◄                                           ├───────────────────────┤
│                                  ┆crosshair┆             │  Bid size │ Price │ Ask size │
│                                                          │  ▇▇▇ 120  │ 5413.00│          │
│──────────────────────────────────────────────────────────│          │ 5412.75│  ▇▇ 85  │ Order Book
│  SUBPLOT: RSI / Volume / MACD  (time-locked)             │  ▇▇▇▇ 310 │ 5412.50│  best   │ (Ladder)
│                                                          │          │ 5412.25│  ▇▇▇ 200│
│                                                          ├───────────────────────┤
│                                                          │  Depth curve  ◢▇▇◣ (glow) │ Depth Visualizer (DV)
├──────────────────────────────────────────────────────────┴───────────────────────┤
│ Positions (2) │ Orders (1) │ History │ Account                  Net P&L: +204   │ Dock (collapsible)
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **LY-01** Chart zone ≈ 68–72% width; sidebar ≈ 28–32%. Draggable vertical divider, snap points at 25/30/35/40%.
- **LY-02** Vertical split inside chart zone: main chart ≥ 60% height; subplot 20–30%; dock collapsed by default (peek 44 pt, expands to 40% height).
- **LY-03** Sidebar order: Quick-Exec (top) → Ladder (flex) → Depth (bottom, ≈ 28% height). Sections collapsible; **ladder keeps minimum 40% height**.
- **LY-04** Safe-area aware; supports **Stage Manager resizing** with adaptive collapse thresholds (compact < 700 pt width → sidebar becomes sheet; < 520 pt → iPhone layout).
- **LY-05** **Touch targets ≥ 44×44 pt** (≥ 56 pt for BUY/SELL, Flatten, Cancel All); spacing ≥ 8 pt between destructive and non-destructive buttons.
- **LY-06** **Handed-ness setting:** mirror sidebar to the left for left-handed users.

### 8.2 iPhone layout (P1)
- Bottom tab bar: **Chart · Trade · Book · Positions · More**.
- Chart tab: chart + collapsible subplot; **floating BUY/SELL mini-bar** pinned bottom with qty chip.
- Trade tab: full ticket with big buttons; Book tab: ladder + depth toggled; Positions tab: list with swipe actions (Close, Edit SL/TP).
- Landscape: chart + slim vertical ticket.

### 8.3 Navigation & modality principles
- Prefer **popovers/inline editing** over full-screen modals during live trading.
- **No navigation can hide the connection status or the live/demo indicator.**
- Sheets for rarely used flows (settings, indicators); **never block the chart** while orders are working.

### 8.4 Keyboard & pointer shortcuts (iPad hardware keyboard) [P1]
| Key | Action |
|---|---|
| `B` / `S` | Arm Buy / Sell (requires `⏎` to confirm unless one-tap) |
| `⏎` | Submit armed order |
| `Esc` | Cancel armed order / dismiss popover |
| `⌘F` | Flatten (with confirm) |
| `⌘⇧X` | Cancel all working orders |
| `← →` | Pan chart; `⌘ + / −` zoom |
| `1…9` | Timeframe presets |
| `C` | Toggle crosshair mode |
| `L` | Lock chart |
| `/` | Symbol search |

---

## 9. UX / CX Definition

### 9.1 UX principles
1. **State is always visible.** Connection, feed, account, environment (live/demo), and session status are visible in the header at all times.
2. **Direct manipulation.** Orders, SL/TP and position management happen *on the chart and ladder* via touch/drag, not in separate forms.
3. **Safety by friction proportional to risk.** Low-risk (view) = none; medium (modify SL) = light confirm; high (market order at large size, flatten) = explicit confirm or hold.
4. **Honest feedback.** Show *pending → working → filled/rejected* states with timestamps; never optimistic-fill.
5. **Progressive disclosure.** Core controls on screen; advanced options in expandable rows/popovers.
6. **Consistency.** Same colour semantics, units and gestures across all panes.

### 9.2 Visual design system (dark-first)

**Palette (initial tokens; adjustable):**
| Token | Dark | Light | Usage |
|---|---|---|---|
| `bg.base` | `#0B0E14` | `#F5F7FA` | App background |
| `bg.surface` | `#121722` | `#FFFFFF` | Panels |
| `bg.elevated` | `#1A2130` | `#EEF1F6` | Popovers |
| `border.subtle` | `#232C3D` | `#D9DFEA` | Dividers |
| `text.primary` | `#E6EAF2` | `#0F1420` | Primary text |
| `text.secondary` | `#8B95A9` | `#5A6477` | Secondary |
| `bull` / `buy` | `#26D07C` (green) or `#3B82F6` (blue scheme) | same | Up candles, bids, buy |
| `bear` / `sell` | `#FF4D6A` (red/pink) | same | Down candles, asks, sell |
| `accent` | `#4DA3FF` | `#1F6FEB` | Selection, crosshair |
| `warn` | `#F5A524` | `#B26B00` | Latency/amber states |
| `osc.yellow` | `#FFD60A` | `#B38F00` | Oscillator line 1 |
| `osc.white` | `#F2F4F8` | `#4A5568` | Oscillator line 2 |
| `depth.bid` | `#4D8DFF` (glow) | | Depth curve bids (blue) |
| `depth.ask` | `#FF5C9A` (glow) | | Depth curve asks (pink) |
| `live.accountBorder` | `#FF4D6A` | | Live-account tint outline |

- **VD-01** **Colour-blind-safe scheme** available (blue/orange) and **colour is never the only encoding** (use ▲/▼, +/−, position, pattern).
- **VD-02** **Typography:** SF Pro (UI) + **SF Mono / tabular numerals** (`.monospacedDigit()`) for all prices, sizes, P&L so digits do not jitter. Sizes: price 15–17 pt, ladder 13–14 pt, badges 12–13 pt bold, labels 11 pt. Supports Dynamic Type for non-trading chrome; trading numerics scale within a bounded range to protect layout.
- **VD-03** **Spacing:** 4-pt grid; panel padding 8/12 pt; ladder row height 22–28 pt (configurable "compact/regular/large").
- **VD-04** **Motion:** short (≤ 150 ms) easing; disable non-essential animation if *Reduce Motion* is on; flashes replaced by subtle outlines.
- **VD-05** **Iconography:** SF Symbols; custom glyphs for candle/line/DOM where needed.
- **VD-06** **Live-account safeguard:** a persistent **red hairline border** around the screen/header and the label **LIVE** whenever connected to a live account; **DEMO** uses blue. Switching environment requires biometric re-auth.

### 9.3 Haptics, sound & feedback
- **FX-01** Haptics (iPhone; iPad where supported): *light* on crosshair snap, *medium* on order submit, *success* on fill, *error* on reject, *heavy* on flatten confirm.
- **FX-02** Optional sound cues (fill, reject, alert, disconnect); respect silent mode; per-event toggles.
- **FX-03** Toasts non-blocking, auto-dismiss 3–5 s, persisted in a notification log; **critical errors are sticky** until acknowledged.

### 9.4 Units, formats & localization
- **UX-U1** P&L display unit selectable globally and per badge: **account currency**, **ticks**, **points**, **% equity**, **R-multiple**.
- **UX-U2** Price formatting honours instrument **digits/tick size** (e.g., ES 0.25 → `5412.25`); thousand separators optional; negative values in red with a leading minus (not parentheses).
- **UX-U3** Locale: English at launch; architecture ready for localization (String Catalogs); RTL-safe layout for non-trading chrome. Time zone selector (UTC / Exchange / Device).
- **UX-U4** Number input uses a **custom numeric keypad** (large keys, tick step ±, quick presets) rather than the system keyboard for speed.

### 9.5 Accessibility (CX inclusive design)
- **AX-01** VoiceOver labels for all controls and **summarized** announcements for live data (e.g., "Position long 2 ES, profit 546 dollars") — **not** per-tick announcements; provide an "Announce P&L" action.
- **AX-02** Contrast ≥ 4.5:1 (text), ≥ 3:1 (graphics); high-contrast mode increases stroke widths & saturates colours.
- **AX-03** Support Bold Text, Increase Contrast, Reduce Motion, Reduce Transparency, Button Shapes.
- **AX-04** Switch Control/Voice Control: all primary trade actions reachable and **named** (e.g., "Buy", "Sell", "Flatten").
- **AX-05** Large-touch mode (increase target sizes) in Settings.

### 9.6 Customer experience (CX) journey

| Stage | Experience goals | Key moments & requirements |
|---|---|---|
| **Discover / Install** | Confidence, clarity | Clear description, privacy policy, risk disclosure |
| **First-run onboarding** | Connect in < 3 minutes | Guided MCP server add (QR/URL paste), test connection, select **DEMO first** (default), pick workspace preset |
| **First trade** | Zero surprise | Interactive coach marks: "Tap BUY", "Drag SL on chart"; demo-account default; explicit confirmation of order summary |
| **Daily use** | Speed + calm | Auto-reconnect, remembers layout, Face ID unlock < 1 s, restores last symbol/timeframe |
| **Stressful moments** (fast market, disconnect) | Control + honesty | Large Flatten, clear banners, never lose order state, post-reconnect reconciliation summary |
| **Review** | Learning | Session summary: trades, P&L, fees, max drawdown; export CSV |
| **Support / troubleshooting** | Self-serve | Diagnostics screen: endpoints, latency graph, last errors, **copy/share log (redacted)** |

### 9.7 Empty / loading / error states (examples)
| Situation | UI treatment |
|---|---|
| No server configured | Illustration + "Add your cTrader MCP server" CTA |
| Auth failed | Inline reason ("Token expired"), re-auth action |
| Loading history | Skeleton candles + subtle progress |
| No positions | Dock shows "No open positions" with tip to place an order |
| Depth unavailable | Placeholder card explaining Level 1 only |
| Market closed | Chart dimmed header "CLOSED — opens in 4h 12m"; order buttons restricted per session rules |
| Order rejected | Red toast with human-readable reason + "Details" (code, server message) |
| Rate limited | Amber banner; automatic back-off; non-critical streams throttled first |

---

## 10. Trading Requirements (`TR-*`)

### 10.1 Instruments & contract handling (futures)
- **TR-01** Support **futures** instruments (index, energy, metals, FX, rates, ags) exposed by the connected cTrader account.
- **TR-02** Per-instrument spec MUST drive all calculations: **tick size, tick value, point value/multiplier, min/max/step volume, margin, trading hours, expiry, currency**.
- **TR-03** Display **contract month & expiry countdown**; warn at **N days before expiry / first notice date** (default 5) with "Roll" helper (P1).
- **TR-04** **Roll helper (P1):** one action to close the expiring contract and open the same size in the next contract (two-leg with explicit confirmation; calendar-spread order if supported).
- **TR-05** Trading **session awareness**: orders disabled/limited during closed/halted states per spec; show reason.

### 10.2 Order types & parameters
| Type | v1 | Notes |
|---|---|---|
| Market | ✅ | With max-slippage protection if supported (`slippageInPoints`) |
| Limit | ✅ | Tick-aligned; validates against marketable-limit behaviour |
| Stop (stop-market) | ✅ | Validate stop side relative to market |
| Stop-Limit | ✅ | Two prices |
| Trailing stop | P1 | Distance in ticks; server-side vs client-side clearly labelled |
| Bracket (entry + SL + TP / OCO) | ✅ | SL/TP attach at entry where supported; otherwise sequentially with safety checks |
| OCO | P1 | Server-side if available |
| Iceberg / TWAP | P2 | If supported |
- **TR-06** TIF: Day, GTC, IOC, FOK, GTD (as supported by MCP/broker); unsupported options hidden, not disabled-without-reason.
- **TR-07** All prices validated/snapped to **tick size**; all quantities to **volume step**, within min/max.
- **TR-08** Each order carries a **client-generated `clientOrderId`** (UUID v4 + short prefix) for idempotency and reconciliation. A retry after timeout MUST reuse the same ID.
- **TR-09** Order labels/comments: app tag (`SRT-iOS`) + optional user note for audit.

### 10.3 Order lifecycle & state machine

```
Draft → Validating → Sending → Accepted(Working) → PartiallyFilled → Filled
                       │            │                    │
                       ▼            ▼                    ▼
                   Rejected     Cancelled/Expired     (SL/TP triggers) → Closed
       Unknown(timeout) → Reconciling → (Working | Filled | Rejected | NotFound)
```
- **TR-10** **Timeout handling:** if no ack within T (default 5 s), state = **Unknown**; UI shows "Verifying…", app queries server by `clientOrderId` and positions/orders before allowing resubmission; **never auto-resend market orders blindly**.
- **TR-11** **Amend/cancel race handling:** if the order fills before cancel arrives, show clear outcome ("Cancel failed — order already filled @ price").
- **TR-12** **Partial fills** shown with filled/remaining and average fill price; remaining qty actions available.
- **TR-13** **Server is the source of truth.** Local P&L is an *estimate*; reconcile positions/orders/account at connect, after each execution event, and every 30 s.

### 10.4 Pre-trade validation & risk controls (`RiskGuard`)
- **TR-20** **Risk-based sizing:** quantity computed from *risk % of equity* (or fixed $ risk) ÷ (SL distance × tickValue/tick) rounded **down** to volume step; shows resulting risk & margin before submit.
- **TR-21** **Max order size** (per order), **max net position** (per instrument), **max total exposure**, **max open orders**, **max daily loss** (soft warn / hard lock), **max drawdown from day high-water**, **max trades per day/hour** — all user-configurable with sensible defaults per account type.
- **TR-22** **Margin check:** estimate required margin from spec and account state; block or warn if free margin insufficient or margin level < threshold (default warn at 150%, block at 100% [OPEN]).
- **TR-23** **Price sanity ("fat-finger") checks:** 
  - Limit price deviates from last by > X ticks/% → warn/confirm. 
  - Marketable limit crossing spread by > X → warn. 
  - Stop on wrong side → block with explanation. 
  - Notional > threshold → explicit confirm with typed quantity.
- **TR-24** **Daily loss lock:** when hit, new risk-increasing orders are blocked until next session reset or manual override (biometric + typed confirmation); **risk-reducing orders (close/reduce/cancel) are always allowed**.
- **TR-25** **Risk-reducing priority:** Close/Flatten/Cancel remain available in degraded states (stale data allowed with warning) as long as connectivity to server exists.
- **TR-26** **Order confirmation policy** (configurable):
  | Action | Default |
  |---|---|
  | Market order (qty ≤ safe size) | Confirm sheet (or one-tap if enabled) |
  | Market order (qty > safe size) | Mandatory confirm with order summary |
  | Limit/stop placement | Light confirm (inline "Place" button) |
  | Modify SL/TP via drag | Confirm toast with "Undo" window 3 s *or* explicit confirm |
  | Cancel single order | No confirm (✕ tap) |
  | Cancel all / Flatten | Mandatory (hold-to-confirm 600 ms or confirm dialog) |
- **TR-27** **Live-account guard:** first order after app launch/relaunch or after environment switch requires biometric auth (setting: *every order* / *first only* / *off*).
- **TR-28** **Kill switch:** prominent control (Settings + header menu) to **cancel all orders + flatten** (account-wide) with confirmation; optionally remote-triggerable via MCP side if the server supports.

### 10.5 Data-quality gating of trading controls
- **TR-30** **Latency gating:** if RTT > threshold (default 1.5 s) or jitter high → amber warning; > 5 s or offline → risk-increasing orders disabled.
- **TR-31** **Stale feed gating:** if last tick age > stale threshold (default 3 s during open session) → BUY/SELL buttons show "STALE" state and require **explicit override tap** (or are disabled, user-configurable); **risk-reducing actions remain enabled with warning**.
- **TR-32** **Account out-of-sync gating:** while `OUT OF SYNC` → disable risk-increasing orders until reconciliation completes.
- **TR-33** **Ladder-click safety:** *Arm-then-tap* mode shows a pulsing armed indicator that auto-disarms after N seconds (default 10).

### 10.6 Positions & P&L
- **TR-40** P&L computed locally: `pnl = (mark − entry) × direction × volume × tickValue/tickSize` using the **correct side price** (long marks to bid, short marks to ask; optional "mid"/"last" setting). Include **commissions and swaps** when provided; display **gross** and **net** options.
- **TR-41** **Aggregated net position** per instrument and account-level **total P&L / equity / margin level** in header & dock.
- **TR-42** **Hedging vs netting accounts** [OPEN: cTrader supports both modes] — UI MUST handle both: per-position rows (hedging) or a single net position (netting). Close semantics: *close position(s)* vs *offsetting order*.
- **TR-43** **Position actions:** Close, Close partial (½, ¼, custom), Reverse (close + open opposite — atomic if supported), Edit SL/TP, Add to position, Move SL to breakeven (+ N ticks offset), Trail from here.
- **TR-44** **Break-even helper:** one tap to move SL to entry ± fees.
- **TR-45** **MAE/MFE** and time-in-trade recorded locally for journaling (P2).

### 10.7 Alerts (P2)
- Price alerts (cross above/below), P&L threshold alerts, margin-level alerts, indicator-based alerts (RSI cross, volume surge), connection alerts. Delivery: local notification while app alive; **push via server relay** when backgrounded [OPEN: requires MCP/server component or APNs relay].

### 10.8 Audit, journal & export
- **TR-50** Immutable local **audit log** of every user-initiated trading action (timestamp, device, action, request payload hash, server response, latency). Redacted export (CSV/JSON).
- **TR-51** **Trade journal (P2):** auto-capture chart screenshot at entry/exit, notes & tags, session statistics (win rate, avg R, profit factor, fees).
- **TR-52** Export executions/positions to CSV; share sheet.

---

## 11. Security & Privacy Requirements

| ID | Requirement |
|---|---|
| SEC-01 | All traffic over **TLS 1.2+ (prefer 1.3)**; ATS enabled; **optional certificate/SPKI pinning** for self-hosted server (user can pin on first connect, TOFU model with change warning). |
| SEC-02 | Credentials/tokens (MCP bearer/OAuth/API key, cTrader tokens if relayed) stored **only in Keychain**, `ThisDeviceOnly`, optionally gated by biometrics. Never in logs, UserDefaults, screenshots, or crash reports. |
| SEC-03 | **App lock:** Face ID/Touch ID/passcode on launch and after N minutes in background (default 1 min); content **blurred in app switcher**. |
| SEC-04 | **Least privilege:** support **read-only token mode** (view-only app) vs **trade-enabled** mode; clear UI when in read-only (order controls hidden/disabled). |
| SEC-05 | OAuth 2.1 / PKCE if the MCP server supports OAuth; otherwise static token with rotation reminders. Token refresh handled transparently; revoke on logout. |
| SEC-06 | **No third-party analytics SDKs** that see trading data. Optional anonymous crash reporting (opt-in) with PII/trading data scrubbed. |
| SEC-07 | **Jailbreak/debugger awareness** (soft): warn if device integrity compromised [P2]. |
| SEC-08 | **Prompt-injection & server-content safety:** treat all MCP tool outputs as **untrusted data** — never execute instructions found in tool results; strict schema validation (reject unexpected fields/types); numeric bounds checks before any order is built. |
| SEC-09 | **Order integrity:** orders are constructed **only from user input in the ticket/UI state**, never from remote text; the user-visible confirmation summary is generated from the *exact* payload to be sent. |
| SEC-10 | Screenshots/screen recording: show a privacy warning; optional "hide balances" mode (privacy mode) for streaming/screen-share. |
| SEC-11 | Data retention: local caches purgeable from Settings; "Sign out & wipe" erases tokens, caches, journal (with confirm). |
| SEC-12 | Compliance with **GDPR/CCPA** for any personal data; provide in-app privacy policy and data-deletion path. |

---

## 12. Non-Functional Requirements

### 12.1 Performance budgets (iPad Pro M-class reference; A14+ minimum)
| Metric | Target |
|---|---|
| Cold launch → interactive (cached) | ≤ 1.5 s (≤ 2.5 s on A14) |
| Connect → first live tick | ≤ 2 s on good network |
| Chart pan/zoom frame rate | ≥ 60 fps (120 fps ProMotion where feasible), < 2% dropped frames |
| Tick → pixels latency (app-side) | ≤ 50 ms p95 |
| Order tap → request on wire | ≤ 50 ms p95 (excluding network) |
| Ladder update | ≤ 100 ms p95 from message receipt |
| Memory (steady, 1 symbol, 5k candles, 40-level depth) | ≤ 300 MB |
| CPU (idle live stream) | ≤ 15% of one performance core average |
| Energy | "Low" impact in Xcode Energy gauge for 1 h session at normal brightness (display excluded) |
| App size | ≤ 60 MB download |

### 12.2 Reliability
- **NFR-R1** Zero data loss for user-initiated orders: every submission is logged *before* send and reconciled after.
- **NFR-R2** Automatic reconnect with state reconciliation; handles Wi-Fi ↔ cellular handoff (`NWPathMonitor`), VPN toggles and airplane-mode transitions.
- **NFR-R3** Crash-free sessions ≥ 99.8%.
- **NFR-R4** Graceful degradation matrix: no depth → L1 mode; no push → polling; no history → live-only; no server → read-only cached view (clearly labelled *offline snapshot*).

### 12.3 Background behavior
- iOS suspends sockets in background; app MUST: stop streams, show "Resuming…" on foreground, and **resync before enabling trading**. Server-side SL/TP protect positions while the app is inactive (**UI must warn if a position has no SL**, TR-60 below).
- **TR-60** **Unprotected position warning:** badge/ribbon on positions without SL (configurable) and prompt to set protection.

### 12.4 Compatibility
- iPadOS/iOS 17.0+ (consider 18+ for newer APIs with fallbacks), arm64 only; Mac Catalyst / "Designed for iPad on Mac" smoke-tested (P2).

### 12.5 Observability
- Structured, redacted logging with levels; in-app **Diagnostics** screen (connection timeline, last 200 events, RTT chart, feed gaps, memory/CPU snapshot) and **shareable support bundle**.
- Metrics (local): tick rate, frame time, indicator calc time, order latencies (send→ack→fill).

---

## 13. Settings Catalogue (selected)

| Group | Setting | Default |
|---|---|---|
| Connection | Server URL, auth, pinning, read-only mode, poll fallback interval | — |
| Trading | One-tap mode, confirm policy matrix, default qty presets, default TIF, default SL/TP ticks, max slippage, reduce-only default | One-tap OFF |
| Risk | All TR-21 limits, daily loss lock, margin thresholds, unprotected-position warning | Conservative |
| Chart | Default TF, chart type, line overlay source, session shading, timezone, auto-scale, price-axis side, grid, crosshair mode, magnet | Candle+Line, 1m |
| Order Book | Levels, row height, heat-bar scale, large-lot threshold, colour scheme, ladder-click mode | 15 levels |
| Appearance | Theme (Dark/Light/Auto), palette, font scale for numerics, handedness, compact mode | Dark |
| Units | P&L unit, price format, volume format | Currency |
| Alerts/Sound/Haptics | Per-event toggles | On (haptics) |
| Security | App lock timeout, biometric for orders, privacy mode, screenshot warning | 1 min |
| Data | Cache size, clear cache, export, sign-out/wipe | — |

---

## 14. Error Handling Matrix (extract)

| Error | Detection | User message | Behavior |
|---|---|---|---|
| Network lost | `NWPathMonitor`, request timeout | "Offline — trading disabled" | Banner, backoff reconnect, disable risk-increasing orders |
| Auth expired | 401/JSON-RPC auth error | "Session expired — sign in" | Pause streams, re-auth sheet, keep UI state |
| Rate limit | 429 / server error code | "Server busy — slowing updates" | Throttle non-critical streams, keep trading channel priority |
| Order rejected (margin) | Reject code | "Not enough margin: need $X, free $Y" | Offer reduce size action |
| Order rejected (market closed) | Reject code | "Market closed. Opens in 4h 12m" | Offer GTC limit |
| Invalid price (tick) | Pre-validation | "Price must be a multiple of 0.25" | Auto-snap suggestion |
| Duplicate/timeout | No ack | "Verifying order status…" | Reconcile via `clientOrderId` |
| Depth gap | Sequence mismatch | (silent) badge "Resyncing" | Snapshot refetch |
| Schema mismatch | Decoder failure | "Server returned unexpected data" | Log, drop message, surface in diagnostics; never act on it |
| Server clock skew | Time offset > 2 s | "Device clock differs from server" | Warning; use server time for candles |

---

## 15. Compliance, Legal & Disclosures

- Risk warning (futures are leveraged and can lose more than initial margin) shown at onboarding and accessible in Settings.
- "Not investment advice" statement; no recommendations/signals unless separately regulated.
- Clear indication that quotes may be delayed depending on the data subscription and exchange agreements; display exchange data-licence notices if required (CME, ICE, etc., typically via the broker).
- Logging of consent (timestamp, version).

---

## 16. Delivery Plan & Milestones

| Phase | Scope | Exit criteria |
|---|---|---|
| **M0 – Discovery (1–2 wks)** | Inspect the real cTrader MCP (tools, schemas, streaming, auth); finalize Appendix A mapping; choose chart rendering approach via spike; confirm Level 2 availability; UX wireframes & hi-fi for iPad landscape | Signed-off contract + clickable prototype |
| **M1 – Foundations (2–3 wks)** | Project skeleton, DI, MCPClient, auth/Keychain, connection state machine, diagnostics screen, mock MCP server for tests | Connect/reconnect demo against mock + real server (read-only) |
| **M2 – Chart Core (3–4 wks)** | Candle+line renderer, gestures, timeframes, history paging, crosshair/HUD, live candle update | 60 fps with 5k candles; crosshair spec CH-20..23 passing |
| **M3 – Indicators & Subplot (2 wks)** | Indicator engine, subplot pane (time-locked), 8 indicators, settings sheet | Parity tests vs reference (OSC-09) |
| **M4 – Order Book & Depth (3 wks)** | Ladder, tape, heat-bars, depth curve, wall detection, slippage estimator, resync logic | OB/DV acceptance tests |
| **M5 – Trading (4 wks)** | Ticket, order types, validation, RiskGuard, lifecycle state machine, positions, P&L badges on chart, SL/TP drag, flatten/cancel-all, audit log | Full demo-account trading flow incl. fault injection |
| **M6 – Header, Layouts, Settings, Polish (2–3 wks)** | Telemetry badges, workspace presets, themes, accessibility, iPhone layout, onboarding | Accessibility audit pass; UX review |
| **M7 – Hardening & Beta (3 wks)** | Soak tests, network-chaos tests, performance tuning, security review, TestFlight beta on demo | Exit metrics in §12 met |
| **M8 – Live-enablement gate** | Controlled live rollout with small size limits | Sign-off checklist (§18) |

---

## 17. Testing Strategy

1. **Unit tests:** pricing/tick rounding, P&L math (long/short, multipliers, fees), risk sizing, validators, indicator parity (golden CSV fixtures), order state machine, depth book apply/gap logic, reconnect/backoff.
2. **Property-based/fuzz tests:** random depth delta streams (book invariants: no crossed book, sorted levels), random order sequences vs state machine, malformed MCP payloads.
3. **Mock MCP server (Swift or Node):** scriptable scenarios — latency injection, packet loss, duplicate messages, out-of-order, disconnects mid-order, rejects, partial fills, market halts, contract roll, schema drift.
4. **Integration tests:** against cTrader **demo** account via the real MCP server (nightly).
5. **UI tests:** XCUITest for ticket flows, confirmations, flatten; **snapshot tests** for chart panes, badges, ladder, depth in dark/light & multiple sizes.
6. **Performance tests:** `XCTMetric` (CPU, memory, hitches), Instruments (Metal System Trace, Time Profiler), 8-hour soak.
7. **Chaos/network tests:** Network Link Conditioner profiles (3G, lossy Wi-Fi), airplane toggle, VPN flap, background/foreground cycles during open orders.
8. **Accessibility tests:** Accessibility Inspector, VoiceOver script, Dynamic Type matrix.
9. **Security tests:** MITM (proxy) with pinning on/off, Keychain inspection, log scraping for secrets, jailbreak-less static checks.
10. **Manual exploratory:** "fast market" playbooks (rapid taps, gesture conflicts), left-handed use, glare/bright-light legibility.

**Definition of Done (feature):** acceptance criteria met, unit + UI tests added, performance budget verified, accessibility reviewed, logging/diagnostics hooks present, docs updated.

---

## 18. Acceptance Criteria — Release Gates

**Functional (must all pass on DEMO, then limited LIVE):**
- [ ] Chart shows candles + line overlay, pans/zooms at ≥ 60 fps with 5k candles.
- [ ] P&L badges anchor at entry price, update every tick, survive pan/zoom, edge-pin correctly, collapse in clusters, unit toggle works.
- [ ] Crosshair shows timestamp + OHLC + indicator values; syncs across chart/subplot/ladder.
- [ ] Subplot time-locked with main chart; indicators match reference within tolerance.
- [ ] Ladder shows correct bid/ask/size with heat bars; depth curve visualizes walls; slippage estimate correct for ticket size within 1 tick on test fixtures.
- [ ] Orders: market/limit/stop/stop-limit/bracket place, amend, cancel, close; partial fills handled; timeouts reconciled with no duplicates in 100 fault-injection runs.
- [ ] RiskGuard blocks/warns per TR-20..28; risk-reducing actions always available.
- [ ] Header telemetry accurate (ping within ±10 ms of reference, stale detection within 1 s of threshold).
- [ ] Reconnect restores streams and reconciles state in < 5 s on stable network; no ghost positions/orders.
- [ ] Live/demo distinction unmistakable; biometric gates work.

**Non-functional:** budgets in §12.1 met; crash-free ≥ 99.8% in beta; zero secrets in logs; accessibility audit passed; App Review checklist satisfied.

---

## 19. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| MCP server lacks streaming/depth | Degraded UX | Polling fallback, L1 mode, request server enhancements; adapter layer |
| MCP is designed for LLM tool-calling (latency, schema verbosity) rather than low-latency trading | Slower than native Open API | Consider a **thin dedicated streaming endpoint** (WebSocket/SSE) on the server alongside MCP; keep MCP for control-plane tools |
| Chart performance on large datasets | Janky UX | Metal renderer, decimation, viewport culling, spike in M0 |
| Order duplication/ghost orders on flaky networks | Financial loss | Idempotency keys, reconcile-before-retry, server as truth |
| Fat-finger / mis-taps on touch UI | Financial loss | Sizing locks, confirmations, debounce, arm-then-tap, daily loss lock |
| Data licensing for exchange futures data | Legal/commercial | Rely on broker-provided entitlements; display notices |
| App Store rejection (financial app policies) | Distribution delay | TestFlight/Ad Hoc for personal use; clear scoping and disclosures |
| Background suspension → missed events | Unmanaged positions | Server-side SL/TP, unprotected-position warnings, optional push relay |
| Prompt injection via tool output | Unauthorized trades | Untrusted-data handling, schema validation, user-originated orders only (SEC-08/09) |
| Floating-point errors in pricing | Wrong P&L/orders | `Decimal` everywhere, tick snapping, test vectors |
| Scope creep (drawing tools, alerts, journal) | Delay | P0/P1/P2 tiers, milestone gating |

---

## 20. Open Questions [OPEN]

1. What are the **exact tools/resources** of your cTrader MCP (names, params, auth, streaming support)? Can you share its tool list or repo?
2. Does your broker feed provide **true Level 2 depth** for the target futures? Which exchanges/instruments?
3. Account mode: **hedging or netting**? Live, demo, or both at launch?
4. **Distribution:** personal (TestFlight/Ad Hoc) or public App Store?
5. Is the setuprush.com UI an **exact visual target** (branding, palette) or an inspiration? Any brand assets/fonts?
6. Preferred **P&L unit** in the badges (the reference shows integers like `+8343`: currency, ticks, or points?).
7. Do you need **push alerts when the app is closed** (needs a server-side relay)?
8. iPhone: required at v1 or follow-up?
9. Preferred remote access method for the MCP server (public HTTPS, VPN, tunnel)?
10. Any regulatory constraints (jurisdiction, licensed entity) affecting the in-app disclosures?

---

## Appendix A — Proposed MCP Tool Contract (to align with the real server)

> Tool names are **proposals**; the app's `MCPAdapter` maps them to actual names. All prices/volumes are strings (decimal) to avoid float loss. All timestamps ISO-8601 UTC or epoch-ms.

### A.1 Read tools
| Tool | Params | Returns |
|---|---|---|
| `get_account` | `accountId?` | balance, equity, margin, freeMargin, marginLevel, currency, mode (hedging/netting), isLive |
| `list_symbols` | `query?`, `assetClass?` | `[InstrumentSpec]` |
| `get_symbol` | `symbol` | `InstrumentSpec` (tickSize, tickValue, multiplier, minVol, maxVol, step, sessions, expiry, digits) |
| `get_trendbars` | `symbol, timeframe, from, to` | `[{t,o,h,l,c,v}]` |
| `get_positions` | — | `[Position]` |
| `get_orders` | — | `[WorkingOrder]` |
| `get_executions` | `since` | `[Execution]` |
| `get_depth_snapshot` | `symbol, levels` | bids/asks arrays, `seq` |

### A.2 Subscription tools / resources (notifications)
| Tool | Params | Notification payload |
|---|---|---|
| `subscribe_quotes` | `symbols[]` | `{symbol, bid, ask, bidSize?, askSize?, last?, t}` |
| `subscribe_depth` | `symbol, levels` | `{symbol, seq, type: snapshot|delta, bids[], asks[], t}` |
| `subscribe_trades` | `symbol` | `{symbol, price, size, side?, t}` |
| `subscribe_account` | — | account/position/order/execution events |
| `unsubscribe_*` | ids | ack |
| `ping` | `clientTs` | `{clientTs, serverTs}` → RTT & clock skew |

### A.3 Trading tools
| Tool | Params | Returns |
|---|---|---|
| `place_order` | `symbol, side, type, volume, price?, stopPrice?, tif, sl?, tp?, slippage?, clientOrderId, label?` | `{orderId, status, reason?}` |
| `amend_order` | `orderId, price?, stopPrice?, volume?, sl?, tp?` | ack |
| `cancel_order` | `orderId` | ack |
| `close_position` | `positionId, volume?` | ack |
| `amend_position` | `positionId, sl?, tp?, trailing?` | ack |
| `flatten` | `scope: symbol|account, symbol?` | `[ack]` |
| `get_order_by_client_id` | `clientOrderId` | state (for timeout reconciliation) |

### A.4 Example payloads

```json
// place_order request
{
  "symbol": "ES",
  "side": "BUY",
  "type": "LIMIT",
  "volume": "2",
  "price": "5412.25",
  "tif": "GTC",
  "sl": "5405.00",
  "tp": "5430.00",
  "clientOrderId": "SRT-3F9A6C1E-6B7D-4F0A-9E1C-1A2B3C4D5E6F"
}
```
```json
// quote notification
{ "symbol":"ES", "bid":"5412.25", "ask":"5412.50", "bidSize":"120", "askSize":"85", "t": 1764191100123 }
```
```json
// depth delta notification
{ "symbol":"ES", "seq": 918273, "type":"delta",
  "bids":[{"p":"5412.25","s":"310","op":"modify"}],
  "asks":[{"p":"5412.75","s":"0","op":"remove"}], "t": 1764191100125 }
```

---

## Appendix B — Calculation Reference

- **Tick count:** `ticks = (price₂ − price₁) / tickSize`
- **Position P&L (account currency):** `ticks × direction × volume × tickValue` (direction = +1 long, −1 short); subtract commissions/fees for net.
- **R-multiple:** `pnl / initialRisk`, `initialRisk = |entry − SL| / tickSize × tickValue × volume`
- **Risk-based size:** `volume = floor_to_step( (equity × risk%) / (|entry − SL| / tickSize × tickValue) )`
- **Depth slippage for size Q (buy):** walk asks accumulating size until ≥ Q; `avg = Σ(price×size)/Q`; `slippage = avg − bestAsk` (in ticks).
- **Cumulative depth curve:** running sum of size outward from mid for each side.
- **Imbalance:** `Σbid_sizes(N) / (Σbid_sizes(N) + Σask_sizes(N))`.
- **Latency RTT:** from `ping` round trips; show median of last 20 and p95 of last 100; clock skew = `serverTs − (clientSend + RTT/2)`.

---

## Appendix C — Glossary
**DOM/Ladder** – price-ordered list of resting bids/asks. **L1/L2** – top-of-book vs multi-level depth. **Tick** – minimum price increment. **Tick value** – account-currency value of one tick per contract. **OCO** – one-cancels-other. **Bracket** – entry with attached SL/TP. **TIF** – time in force. **MAE/MFE** – max adverse/favourable excursion. **R-multiple** – P&L expressed in units of initial risk. **Hedging/Netting** – multiple independent positions per symbol vs a single net position. **MCP** – Model Context Protocol (JSON-RPC 2.0 based tool/resource protocol).

---

*End of specification.*
