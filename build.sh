#!/bin/bash
# Convenience entry point: run this from the project root (./build.sh) to build the
# release binary and package it as TradersRush.app. Thin wrapper around the real script
# so it doesn't need to live at the repo root.
set -e
cd "$(dirname "$0")"
./AppPackaging/make_app.sh
