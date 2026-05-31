# GuildHub

A modern guild social window for World of Warcraft (Retail). Replaces the default guild/communities frame with a feature-rich hub for managing members, teams, events, recruitment, persistent chat, and more.

## Features

- **Members tab** — Searchable roster with rank, class, level, zone, and last-online info. Inline public/officer note editing, promote/demote/kick actions, and per-member profile panels with alts, join dates, and personal notes.
- **Teams tab** — Create named groups (raid teams, PvP teams, etc.) from guild members. Officers can manage rosters; members can apply.
- **Events tab** — In-game event scheduling and sign-ups, separate from the default calendar.
- **LFM / Recruit tab** — Looking-for-members board. Post open slots, set requirements, and manage applicants.
- **Guild Recruit tab** — Guild-side recruitment post builder for advertising to players searching for a guild.
- **Chat tab** — Persistent guild chat history that survives reloads and relog, plus BNet whisper support.
- **Activity tab** — Running log of guild events: joins, leaves, rank changes, and custom entries.
- **Communities tab** — View and interact with Battle.net communities alongside your guild.
- **Player profiles** — Cross-session profiles with notes, alts, join date, and birthday tracking.
- **Profile sync** — Syncs profile data between online guild members via addon messages.

## Installation

1. Download or clone this repository into `World of Warcraft/_retail_/Interface/AddOns/GuildHub/`.
2. Launch or reload WoW (`/reload`).
3. Enable **GuildHub** in the AddOns list on the character select screen.

## Usage

| Command | Action |
|---|---|
| `/gh` | Open GuildHub |
| `/gh members` | Jump to Members tab |
| `/gh chat` | Jump to Chat tab |
| `/gh teams` | Jump to Teams tab |
| `/gh events` | Jump to Events tab |
| `/gh lfm` | Jump to LFM tab |
| `/gh activity` | Jump to Activity log |
| `/gh settings` | Open settings panel |
| `/gh reset` | Reset all saved data |
| `/gh debug` | Toggle debug logging |
| `/roster` | Shortcut to Members tab |

You can also click the minimap button (draggable to any position) or press **G** — GuildHub intercepts the default guild keybind so the default Communities frame never opens.

## Requirements

- WoW Retail, Interface version **120005** or later.
- No external library dependencies (BNetChatThrottleLib is bundled).

## Version

**0.81**

## Author

Storm
