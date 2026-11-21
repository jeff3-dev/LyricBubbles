# Changelog

## 0.1.0 (first public release)

### New
- **Playback controls** in every style window: play/pause, previous and next for Spotify, in a small
  glass capsule above the song caption. Each style has its own setting: Off, On Hover (default) or Always.
- **Playback menu** with Play/Pause (⌥⌘P), Previous (⌥⌘←) and Next (⌥⌘→).
- **Transport buttons on the dashboard's Now Playing card.**
- **General settings pane**: launch window, Float on Top, lyric timing (with a Reset button) and React to Music.
- **Per-song timing fix**: if one song's lyrics run early or late, nudge just that song with ⌥⌘[ / ⌥⌘]. It's
  remembered for that song. Reset it from the Playback menu or the "This song" row in General settings.
- **Welcome notice** on first launch, explaining what the app does, where lyrics come from and what it
  doesn't do with your audio.

### Improved
- **Tighter lyric sync**: the playhead is read on its own and timed more accurately, small drift is corrected
  within about a second instead of about twelve, and one bad reading from Spotify can no longer make the
  lyrics jump. Spotify keeps being checked while a new song's lyrics load.
- **Less lag**: style windows no longer redraw their whole view once a second while a song plays.
- **Night Sky rework**: the camera now cruises forward without ever stopping or jerking, each line's
  constellation comes out of deep space toward you as it's sung, and the warp builds up over the seconds
  before a chorus and eases off as it starts, instead of cutting in and out.
- **Full screen Messages** now fills the whole display at any aspect ratio, scaling the thread up for
  large screens, instead of a narrow portrait column. Long lines wrap at a readable width.
- **Dashboard redesign**: cleaner header, preview tiles with names and short descriptions underneath,
  keyboard shortcut hints on hover, and a plain native background in light and dark mode.
- **Consistent settings across all nine styles**: the same section headings, labels, switches, sliders,
  value read-outs and help text everywhere, and the Playback setting pinned to the same place in every pane.
- React to Music moved from the Messages pane to General, since it affects every style.
- Float on Top moved to the Styles menu, since it applies to every style window.
- Shorter, clearer style descriptions.

### Removed
- Beta notice, "Beta" watermark, dashboard beta line and the developer-code unlock.
- The "More styles coming" placeholder card.
- Developer snapshot commands are now in debug builds only.
