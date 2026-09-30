# Relic RNG: Museum Heist

Roblox RNG collector / museum tycoon / heist game. Place: "Relic RNG" (placeId 77617461925515).

## Source of truth

Right now the game is edited **in Roblox Studio** (through the Studio MCP), and `src/` is a
byte-exact mirror of every script, refreshed after each round of work. Nothing outside scripts
(world models, the museum plots, dig sites) lives in `src/`; those stay in the place file.

To switch to a Rojo workflow later (files become the source of truth):

1. Install the toolchain: `rokit install` (pins in `rokit.toml`)
2. Refresh the mirror so `src/` matches Studio exactly, then save the place.
3. `rojo serve`, and connect with the Rojo Studio plugin.

From then on edit files, not Studio scripts — Rojo overwrites Studio scripts from `src/`.

## Structure

- `src/shared` → `ReplicatedStorage/RelicRNG` — Config, Types, RemoteNames, RelicModels, FeatureConfig/*
- `src/server` → `ServerScriptService/RelicRNG`
  - `Main.server.luau` — the only server Script: creates remotes, player lifecycle, rolling, income,
    two-phase startup of every module in `Services/`
  - `DataService` (UpdateAsync + session locking + schema migrations), `RollService`, `RateLimit`,
    `MuseumService`, `CodeList` (server-only codes), `HeistMaps`
  - `Services/` — one module per feature (Codes, Daily, Shop, Forge, Collections, Security, Heist,
    Store, Leaderboards, Boosts, CheatCommands, WorldInteractions)
  - `Tests/` — pure-logic specs + `TestRunner`
- `src/client` → `StarterPlayerScripts/RelicRNGClient` — the only LocalScript; `UIKit` + `Features/*`

## Checks

- Unit tests (Studio, Edit mode, command bar):
  `print(require(game.ServerScriptService.RelicRNG.Tests.TestRunner).run())`
- Unit tests without Studio (terminal or CI, from the repo root): `lune run tests/run`
  (`tests/run.luau` rebuilds the Rojo tree from `default.project.json` and runs the same specs).
- QA: in Studio (or as the place creator in a live server) the **Dev** menu button opens cheat
  tools (coins, levels, pity, thieves, heist energy, profile reset). The server re-checks access.
- Format: `stylua src` · Lint: `selene src`
