# Changelog

## [1.4.0] — Translator Ultimate

### Added

- Added translation support for **server messages, player chat and outgoing chat**.
- Added **two incoming chat modes**: replace the original message or display the translation below it.
- Added **automatic translation of outgoing messages**.
- Added translation support for **dialogs**.
- Added translation support for **TextDraws**, including text updates.
- Added translation support for **3D world labels**.
- Added translation support for **player chat bubbles**.
- Added **per-server language profiles** using the connected server address.
- Added **automatic server-language detection** for `AUTO` mode.
- Added **persistent menu translation cache**.
- Added **pending-request deduplication** so identical requests share a single translation job.
- Added **translation queue limits and request priorities** for chat, dialogs, 3D text, bubbles and TextDraws.
- Added **stale-result protection** using versioned delivery entries.
- Added **protected-term masking** so SA-MP commands, color codes and important game terminology survive translation.
- Added **Latin/Cyrillic and Central European encoding handling** for CP1251, CP1252 and CP1250.
- Added **safe Google response validation** before CJSON decoding.
- Added **configurable keyboard shortcuts** through the menu and `/trkey`.
- Added a new **six-section configuration interface** with FAQ and hotkey pages.
- Added **automatic update support** through `translator_updater` when available.
- Added Romanian (`RO`) as a supported language.

### Improved

- Reworked the translation architecture around a queued asynchronous pipeline.
- Improved rendering/replay for translated dialogs, chat RPCs, server messages and world text.
- Improved handling of repeated and rapidly changing TextDraw/3D text content.
- Improved persistence of configuration across different servers.
- Improved filtering of UI noise, game titles and non-translatable text.
- Improved Unicode normalization and conversion of translated text back into SA-MP-compatible encodings.
- Reworked the configuration menu and increased its overall capacity and organization.

### Fixed

- Prevented malformed or non-JSON responses from being sent directly to the JSON decoder.
- Reduced the chance of duplicate requests for the same text.
- Prevented delayed asynchronous translations from replacing newer content.
- Improved handling of translation failures and request timeouts.

### Internal

- Replaced the previous decompiled/obfuscated 1.2 layout with a structured 1.4 codebase.
- Expanded the internal translation pipeline from a single pending request to a managed queue with multiple delivery types.
