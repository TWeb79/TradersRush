# TraderRush

**Beta 0.3** — a native macOS SwiftUI trading-terminal prototype, built against a
mock gateway ahead of a real [cTrader](https://ctrader.com) MCP connection.

![TraderRush screenshot](docs/screenshot.png)

> All prices, order-flow and order-book data on screen are synthetic (clearly
> labeled **MOCK DATA** in the header, flips to **LIVE (MCP)** only once a real
> candle-history tool call actually succeeds). There is no real market connection, no
> account, and no real money at risk — this is a UI/UX prototype.

**New in 0.3:** a real MCP connection layer — config sheet, enable toggle, and a footer
status indicator — that genuinely attempts the MCP handshake and a candle-history tool
call rather than just toggling a label; a second, more reliable zoom path (⌥+scroll); and
the app's rename from SetupRush Trader to TraderRush.

## What's in this build

- **Chart**: candlestick rendering, pinch-to-zoom and ⌥+scroll zoom (both anchored at the
  cursor/pinch point), pan, and live entry/SL/TP lines for open positions — SL updates
  automatically as BE/TSL ratchet it, and the lines disappear the moment a position closes
- **MCP connection**: a config sheet (gear icon) with editable host/port/path/TLS/auth
  fields and an explicit Save, an Enable toggle, and a footer status indicator
  (disabled/connecting/connected/failed). Enabling it performs a real MCP `initialize` →
  `tools/list` → `tools/call` round trip; if your server exposes a recognized
  candle-history tool, real data replaces the mock chart — otherwise it reports exactly
  why not, and stays in Demo Mode. Never claims "live" without data to show for it.
- **Footprint / order-flow view**: Bid×Ask and Delta display modes, with a
  zoomed-in numeric tier (bid/ask/delta per price level) built on the causal
  bid/ask-split construction from the DeltaTrader order-flow playbook
- **Account budget**: a balance header above the ticket, colored relative to the starting
  balance, with an animated digit-roll when a position closes
- **Order ticket**: Buy/Sell, quantity, and a full SL / TSL (trailing stop) / TP /
  BE (breakeven) bracket
- **Synthetic DOM ladder** with heat-bars, clearly labeled as mock
- **Positions/Orders dock**, scrollable, with honest empty states — positions are never
  fabricated; they only appear from your own simulated trades
- **Execution safety toggles**: require confirmation before every trade (default on) and
  opt in to trackpad swipe-trading (default off), each with a one-time risk alert on the
  riskier transition
- **Two execution paths**:
  - keyboard (`B`/`S` + Return) or ticket buttons, with an arm-then-confirm banner
  - a trackpad two-finger **pull-to-arm gesture**: a center ring with a knob that
    blends from grey to green/red as you pull, and a directional arrow outside
    the ring — release past the ring to submit, release inside it to cancel
- **Simulated position lifecycle**: a local random-walk price ticker resolves
  SL/TP/TSL/BE in real time, so brackets are actually demoable, ending with a
  floating **+€ / -€** close alert. This simulation is explicitly flagged in code
  to be disabled once a real market/gateway connection exists.

See [`BACKLOG.md`](BACKLOG.md) for the full feature gap analysis against the
product spec and a prioritized roadmap, and
[`SETUPRUSH_TRADER_PROJECT_SPEC.md`](SETUPRUSH_TRADER_PROJECT_SPEC.md) for the
full product/UX/trading requirements this prototype is working toward.

## Running it

Grab the latest `.app` from [Releases](../../releases), or build from source:

```bash
swift build
.build/debug/SetupRushTrader
```

To package a real `.app` bundle (for dragging to the Dock):

```bash
./build.sh
```

Requires macOS 14+.

## Disclaimer

This is a prototype trading-UI client, not a broker and not financial advice.
No live trading, no real account connection, no real money.
