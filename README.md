<p align="center">
  <img src="https://img.shields.io/badge/Version-1.4.0-blue">
  <img src="https://img.shields.io/badge/Status-Stable-green">
  <img src="https://img.shields.io/badge/Platform-GTA%20San%20Andreas-lightgrey">
  <img src="https://img.shields.io/badge/Framework-MoonLoader%20%7C%20mimgui-red">
  <img src="https://img.shields.io/badge/License-MIT-yellow">
</p>

# 🌐 Translator Ultimate Mod

**Translator Ultimate** is an in-game translation mod for GTA: San Andreas / SA-MP built for MoonLoader.

It translates incoming and outgoing text while preserving the original SA-MP presentation as closely as possible. The 1.4.0 release expands the translator from a basic chat utility into a broader text-translation system covering chat, dialogs, TextDraws, 3D labels and player chat bubbles.

##  What's new in 1.4.0

- **Full chat translation pipeline** for server messages, player chat and outgoing messages.
- **Two chat translation modes:**
  - **Replace text:** replaces the original player message with the translation.
  - **Translation below:** keeps the original message and adds the translated text underneath.
- **Automatic outgoing translation:** translates normal messages before they are sent, while leaving commands beginning with `/` untouched.
- **Dialog translation** with translated titles, buttons and body text.
- **TextDraw translation**, including dynamic TextDraw string updates.
- **3D world text translation** for properties, jobs and interactive labels.
- **Player chat bubble translation** with duration-aware delivery.
- **Automatic server-language detection** when `AUTO` is selected, with per-server language profiles.
- **Per-server configuration persistence** based on the connected server address.
- **Translation queue and prioritization** to prevent translation bursts from overwhelming the client.
- **Request deduplication:** identical pending translations share the same request instead of creating duplicates.
- **Translation cache** with persistent on-disk storage for repeated game text.
- **Protected game terms and formatting:** commands, SA-MP color codes, known game terms and special markers are preserved during translation.
- **Improved character encoding support** for CP1251, CP1252 and CP1250.
- **Safer Google response parsing:** malformed/HTML responses are rejected before JSON decoding.
- **Configurable hotkeys** from the menu or `/trkey`.
- **Expanded configuration UI** with dedicated sections for translation, languages, appearance, FAQ, credits and hotkeys.
- **Optional automatic update support** through the project's updater module.

##  Commands

| Command | Description |
|---|---|
| `/tr <text>` | Translate and send a message using the configured outgoing language. |
| `/autotr` | Toggle automatic incoming/outgoing chat translation. |
| `/trmenu` | Open or close the Translator Ultimate configuration menu. |
| `/trkey <menu\|auto> <key\|off>` | Configure a hotkey from chat. |
| `/trlocale` | Display the current Russian locale information. |

### Example

```text
/tr hello everyone
```

The message is translated into the configured outgoing language before being sent.

##  Supported languages

- Spanish (`ES`)
- Portuguese / Brazil (`PT-BR`)
- English (`EN-US`)
- Russian (`RU`)
- Polish (`PL`)
- Indonesian (`ID`)
- Turkish (`TR`)
- Czech (`CS`)
- Romanian (`RO`)
- Automatic (`AUTO`)

##  Configuration

The configuration menu provides separate controls for:

### Translation

- Chat replacement mode
- Translation below the original message
- Automatic outgoing translation
- Dialogs / menus
- TextDraws
- Above-head chat bubbles
- 3D world text
- Clan-only filtering
- Automatic update checks

### Languages

- Language to display
- Language to send
- Server text encoding / automatic server-language detection

### Appearance

- Dynamic HUD color
- Custom accent color

### Hotkeys

Keyboard shortcuts can be changed directly from the configuration menu or with `/trkey`.

##  Installation

1. Install **MoonLoader** and the required dependencies for your SA-MP setup.
2. Place the released `translator.luac` file in:

```text
GTA San Andreas/
└── moonloader/
    └── translator.luac
```

3. Start GTA: San Andreas and connect to a SA-MP server.
4. Use `/trmenu` to configure your languages and translation options.

##  How the translation pipeline works

Translator Ultimate processes translation requests through a local pipeline rather than sending every text event independently:

```text
Game text
   ↓
Normalization & filtering
   ↓
Cache lookup
   ↓
Pending-request deduplication
   ↓
Priority queue
   ↓
Translation request
   ↓
Validation & decoding
   ↓
Cache result
   ↓
Rebuild original SA-MP element
```

This architecture is designed to reduce duplicate requests, keep repeated text fast, and prevent stale asynchronous results from overwriting newer game text.

##  Distribution

The public release is distributed as compiled `.luac` code. The repository can therefore contain the release artifact without exposing the editable Lua source.

##  Compatibility notes

Translator Ultimate relies on the MoonLoader ecosystem, including `mimgui`, `effil`, `encoding`, `iconv`, `inicfg`, `memory` and, when available, `samp.events`.

Some advanced translation features depend on the SA-MP event/RakNet functions exposed by the user's MoonLoader environment.

##  Support

For bug reports and feature requests, open a GitHub Issue with:

- your MoonLoader version,
- the SA-MP client/server you are using,
- the exact error from `moonloader.log`,
- and the steps required to reproduce it.

---

**Translator Ultimate — by NauTaro**
