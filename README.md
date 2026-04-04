# SloPitch

SloPitch is a Phoenix LiveView app for scoring slo-pitch games on a single device.
It supports roster management, lineup setup, live at-bat scoring, inning-based opponent tracking, and season stats.

## Current MVP Features

- Roster management:
  - Add players (name + jersey number)
  - Toggle players active/inactive
- Game management:
  - Create scheduled games (opponent, date, location, home/away side)
  - View scheduled, in-progress, and final games
- Lineup setup:
  - Build batting order from active roster
  - Reorder, remove, and add players from bench
- Live scoring:
  - Track plate appearance outcomes: `1B`, `2B`, `3B`, `HR`, `OUT`
  - Track balls/strikes and auto-record `walk` and `strikeout`
  - Skip a batter
  - Insert a bench batter for a plate appearance
  - Runner destination confirmation modal for `1B`/`2B`/`3B`/`OUT` when bases are occupied
  - Auto-calculate runs scored and RBIs from end-base state
  - Undo support for both offense events and opponent half-inning events
  - Full game reset button (for testing/restarts)
- Opponent tracking:
  - Opponent runs and outs tracked inning-by-inning
  - Separate defense controls during opponent half-inning
  - State-machine style half-inning transitions (offense/defense) with inning progression
- Game rules implemented:
  - Half inning ends at `3 outs` or `5 runs`
  - Game ends after 7 innings
  - If home team is already ahead entering bottom of 7th, game ends
  - Team home run counts tracked separately (`home` / `away`)
  - HR differential cap enforced: one side cannot lead by more than 2 HR
- Reporting:
  - Game summary with baseball-style line score table
  - Batting lines per game
  - Season and last-5 stats views with sorting

## Routes

- `/` and `/games` - Game center
- `/games/:id/setup` - Lineup setup
- `/games/:id/scoring` - Live scoring
- `/games/:id` - Game summary
- `/roster` - Roster management
- `/stats` - Season/last-5 stats

## Tech Stack

- Elixir + Phoenix 1.8 + LiveView
- Ecto + PostgreSQL (`postgrex`)
- Tailwind CSS + esbuild
- Credo + Dialyzer configured for static analysis

## Getting Started

1. Start PostgreSQL locally and create the default databases:
   - `createdb slo_pitch_dev`
   - `createdb slo_pitch_test`
2. Install dependencies and set up the database:
   - `mix setup`
3. Start the server:
   - `mix phx.server`
4. Open:
   - `http://localhost:4000`

If your local PostgreSQL credentials differ from the defaults, set:

- `DB_USERNAME`
- `DB_PASSWORD`
- `DB_HOSTNAME`
- `DB_PORT`
- `DB_NAME`

## Docker Compose

To run the app and PostgreSQL together in Docker:

1. Start the services:
   - `docker compose up --build`
2. Open the app:
   - `http://localhost:4000`

The Compose setup:

- Starts PostgreSQL 17 on `localhost:5432`
- Starts Phoenix on `localhost:4000`
- Runs `mix deps.get`, `mix ecto.create`, and `mix ecto.migrate` before booting the app
- Persists database data in a named Docker volume

## Database Notes

Key entities in the tracking context:

- `players`
- `games`
- `game_lineup_slots`
- `game_innings`
- `plate_appearances`

Migrations live in `priv/repo/migrations`.

Production expects `DATABASE_URL`, for example:

- `ecto://postgres:postgres@db.example.com/slo_pitch_prod`

## Development Commands

- Run tests:
  - `mix test`
- Format:
  - `mix format`
- Lint:
  - `mix credo --strict`
- Type checks:
  - `mix dialyzer`
- Full local check used in this project:
  - `mix precommit`

## Current Scope

This app is intentionally designed for a single scorekeeper/session (no multi-user auth, no conflict resolution).
