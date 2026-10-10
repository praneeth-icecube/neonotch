# How NeoNotch works

Notes on the parts of NeoNotch that aren't obvious from reading the code: why things are built the way they are, and the traps that shaped them.

- [Geometry](#geometry)
- [The window](#the-window)
- [Shape](#shape)
- [Look](#look)
- [Music](#music)
- [Apple Clock](#apple-clock)
- [Drops](#drops)
- [The lock screen](#the-lock-screen)
- [Smooth clocks](#smooth-clocks)
- [Debugging](#debugging)
- [Signing and distribution](#signing-and-distribution)

## Geometry

### Real and virtual notches

`NotchGeometry` reads the display's `safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. On a notched display these describe the camera housing exactly, and the island takes its size. On a Mac without a notch the insets are zero, so NeoNotch draws a **virtual notch**: a black island the height of the menu bar, centred at the top of the screen, with the same concave "ears" a real notch has, so it melts into the menu bar rather than sitting on top of it.

Moving between displays updates the island automatically. **Settings → Notch size and position** can force the virtual notch on either kind of display and adjust its width, height and horizontal offset.

### Idle and busy

The closed island has two shapes, and **it only ever grows sideways**:

| | Size | When |
| --- | --- | --- |
| **Idle** | 210 × menu bar height | Nothing running |
| **Busy** | 320 × menu bar height | Timer, stopwatch, focus session or playback |

Its height is pinned to the menu bar, so the closed island never reaches into the area where you work. That is the constraint everything is built around: only the open panel is allowed to drop into the workspace, because by then you are looking at it on purpose.

The cost is menu items. macOS lays out the menu bar with no idea that a virtual island exists (on a notched display the system reserves the cutout and moves menus around it), so a busy island can cover the tail end of a long app menu. Staying out of the workspace is worth more than the last menu title. Every 2 pt taken off the width in Settings uncovers 1 pt of menu bar on each side.

### Alignment

The panel is centred on the display's logical frame and rounded to whole points, and the island is centred inside it with an even width, so it always lands on an exact point.

The **readout is centred too**, which matters more than it sounds. Laying the icon and the time out as one centred group is the obvious approach, and it's wrong: it pushes the number about 11 pt right of the island's centre line. The eye lines the number up against the camera, so the island then looks as if it extends too far left even though it is centred to the pixel. `CollapsedView` centres the readout in a `ZStack` and gives the icon a mirrored gutter on the right, filled with a progress ring or level bars. The island is then balanced by visual weight as well as by geometry.

If the island still looks off-centre, the cause is usually that the screen isn't perfectly centred in the laptop's lid. **Settings → Notch size and position → Move left / right** nudges it up to ±60 pt for that case.

## The window

The panel is a borderless, non-activating `NSPanel` at `.screenSaver` level, so it draws above the menu bar and above full-screen windows. It has a fixed size: wide enough for Home with every widget on, plus its shadow. It is transparent everywhere except the island itself.

Every tab opens at the same width as Home. Hovering a tab switches to it, so a panel that resized per tab would slide the tab strip out from under the pointer, which would then land on another tab and switch again. Tabs that don't need the full width centre their content instead.

### Click-through

`PassthroughHostingView` overrides `hitTest(_:)` and returns `nil` for any point outside the island's current rect, so clicks in the transparent area fall through to the menu bar and whatever app is underneath. The rect is kept in window coordinates (origin at the bottom left), to avoid guessing between flipped and unflipped coordinates.

Two edge cases the island depends on, both easy to get wrong without noticing:

- `PassthroughHostingView` returns zero `safeAreaInsets`. The panel deliberately overlaps the menu bar, and AppKit responds by insetting the hosting view. That pushes the island down, leaves dead space above it, and makes the top of the island unclickable while it still looks solid.
- The hover rect is padded 8 pt **above** the island. Its top edge is the screen's top edge, and `CGRect.contains` treats `maxY` as exclusive. Without the padding, the exact row of pixels the pointer lands on when you throw it at the top of the screen would be the one row that doesn't register.

### Pointer tracking

The primary signal is a 10 Hz poll of `NSEvent.mouseLocation`, with `NSEvent` monitors as a zero-latency accelerator. The poll is what makes it reliable: move events don't reach a background agent in every situation, such as over another app's full-screen surface, during a drag session, or when the pointer is warped rather than moved.

While something runs full screen on the display, the island steps out of the way.

## Shape

`NotchShape` is modelled on the MacBook Pro camera housing. Two things make it read as a notch rather than a floating pill:

- **True circular fillets.** Every corner is built with `addArc(tangent1End:tangent2End:)`, which is tangent to both edges by construction. Quadratic curves with the control point on the corner come close to a circle but aren't one, and they look soft and inflated.
- **The right ratios.** The real notch is about 37 pt tall with roughly a 10 pt bottom radius and a 5–6 pt ear, so the bottom corner is about a quarter of the height and the ear about a sixth. `NotchShape.macBookPro(height:)` scales those to whatever height the island is. The real shape is squarer than people tend to remember it.

The closed island uses these ratios. The open panel keeps its own softer radii, because at that point it is a panel, not a notch.

One difference is deliberate: a real notch is about 172 × 37 pt (≈4.6:1), while the idle virtual island is 210 pt wide and only as tall as the menu bar. A 37 pt island would hang below the menu bar and into the workspace.

## Look

Content sits straight on the black, with no cards, and sections are divided by hairlines. Hierarchy comes from white at a few fixed opacities (`NotchTheme`) rather than from boxes, which keeps a panel this small from looking cluttered. Tabs are icons only, with the title as a tooltip. While a song plays, the Music tab's icon becomes level bars in the cover's colour, so you can see that it's playing from any tab.

Tabs are 40 pt wide and 12 pt apart. Hovering a tab switches to it only after the pointer has rested there for 0.15 s, while a click switches at once. With tabs packed tightly and switching on contact, the slightest overshoot, or a diagonal move down into the panel, lands on the neighbouring tab. The icon brightens the moment the pointer arrives, so the delay never feels like lag.

## Music

Now-playing information arrives on two channels:

- **Broadcasts.** Spotify posts `com.spotify.client.PlaybackStateChanged` and Music posts `com.apple.Music.playerInfo` on every play, pause and track change. Receiving them needs **no permission**, and they arrive instantly, so a song shows up the moment it starts even if Automation was never granted. They are registered with `.deliverImmediately`: AppKit suspends distributed notifications while an app is inactive, and an agent app is inactive nearly all the time, so without that flag every broadcast would wait for your next click.
- **Apple Events.** Controls, volume, Music's playback position and the embedded cover need Automation permission. With it, a 2.5 s poll keeps position and volume accurate. The scrubber itself is extrapolated from an anchored clock, so it moves smoothly without the model publishing every frame.

Durations are a classic trap: both broadcasts report milliseconds, Spotify's Apple Events report milliseconds, and Music's Apple Events report seconds.

**AppleScript reserved words.** Every script variable carries an `nn` prefix. An early version stored player state in a variable called `st`, which is reserved in AppleScript (it's the ordinal suffix, as in `1st`). The script failed to compile, every query died before reaching the player, and the error was swallowed as "Nothing playing". `--selftest-music` now compiles each script against the player's real dictionary, so a mistake like that fails a check instead of showing up while you're listening.

**Permission.** The first time a player is seen running, NeoNotch asks macOS once, with the standard "NeoNotch wants access to control Spotify" dialog. If you decline, the player still shows up through broadcasts, and the controls swap the volume slider for a **Turn on in Settings** button that opens Privacy & Security → Automation. Access switched on there is picked up within ten seconds, without a relaunch. Pressing a control before access was ever requested shows the dialog first and then performs the press.

**Covers** come from the most exact source available: the player itself over Apple Events, then, needing no permission, Spotify's public oEmbed endpoint for Spotify tracks or the iTunes Search API (matched on artist) for Apple Music. Those requests send the track's ID, or its artist and album, only to the company whose catalogue it is already in. The cover's dominant colour tints the level bars, and a near-greyscale cover stays neutral rather than getting an invented colour.

When playback pauses, the closed notch keeps the live activity for 2.5 s with flat bars, so skipping a track doesn't make the island jump in and out.

## Apple Clock

Timers and the stopwatch you start in Clock show up in the notch within a second, with nothing to set up. Clock keeps them in its daemon, `mobiletimerd`, in a preferences domain (`com.apple.mobiletimerd`) that other apps of yours can read. Each timer is saved with its fire time (a date while it runs, the time left otherwise), and the stopwatch with its state, start date and offset. `ClockBridge` polls that domain once a second, and `TimerModel` follows whatever it finds: pause, resume or stop something in Clock and the notch follows. NeoNotch's own timer keeps the notch while it runs. A Clock timer that runs out gets the notch's ring but not its chime, because Clock plays its own.

Going the other way is harder:

- The daemon only talks to Apple-signed apps (Clock carries the private `com.apple.private.mobiletimerd` entitlement), and Clock has no AppleScript dictionary.
- Clock's App Intents (`TimerAppIntents`, `StopwatchAppIntents`) are only available to Siri.
- `MobileTimerSupport` does give Shortcuts real Clock actions: Start, Pause, Resume and Cancel Timer, and Start, Stop, Lap and Reset Stopwatch.
- A ready-made shortcut file can't ship with the app, because `shortcuts sign` needs an iCloud account at signing time.

So NeoNotch runs shortcuts you create once, found by name and run with `/usr/bin/shortcuts`. Each shortcut holds one Clock action and is named after it, such as **NeoNotch Start Timer** or **NeoNotch Cancel Timer** (the full list is in the README and in Settings → Apple Clock). Every shortcut is optional. NeoNotch uses whichever exist, and controls without a shortcut offer **Open Clock** instead. Without Start Timer, a timer started in the notch is NeoNotch's own. A timer sent to Clock shows immediately and is swapped for Clock's own entry once Clock reports it. If Clock never reports it, the timer stays in NeoNotch so it still rings.

World clocks are out of reach: Clock keeps them in a protected group container (`group.com.apple.mobiletimerd`) that no other app may read.

## Drops

Drops are handled in AppKit, on `PassthroughHostingView`, not with SwiftUI's `onDrop`.

That isn't a style preference. SwiftUI normalises the type list you give it: asking for `[.fileURL, .image, .pdf, .text, .url, .item]` registers exactly two types with AppKit, `public.data` and `public.item`. **`public.file-url` is never registered**, and that is the type Finder puts on the pasteboard when you drag a file. The notch silently refused every file, with no error anywhere. Inspecting `registeredDraggedTypes` is what exposed it.

Explicit registration now covers `public.file-url`, `NXFileContentsPboardType`, plain text, TIFF, PNG, PDF, URL, RTF and HTML, and `ShelfModel.accept(pasteboard:)` reads the drop straight off the pasteboard in priority order, with no type negotiation in between.

### Catching the drag early

Waiting for the drag to reach the drop target is too late, because the target is a small strip in the menu bar that you would have to hit before anything reacted. Instead, the pointer poll watches for an incoming drag and snaps the panel open onto the Shelf from a **610 × 160 pt** approach zone at the top of the display, with no hover delay and a faster spring. By the time the drag arrives, the whole panel is the drop target.

There is no public "is a drag happening anywhere" API, so `NotchDragTypes.isDragInFlight` infers it, and the obvious inference is wrong. "A button is held and the drag pasteboard offers a type we accept" sounds right, but **the drag pasteboard keeps its contents after the drag ends**. Once anything had ever been dragged, every ordinary click matched, and the notch flew open on the Shelf for no visible reason.

What actually marks a drag is that the pasteboard gets *rewritten* when one starts. So the baseline change count is captured whenever no button is held, and a drag counts as in flight only once that count changes while a button is down. `NotchDragTypes.dragInFlight` is a pure function, and `--selftest-drop` covers its truth table, including the stale-pasteboard case.

> Never write to `NSPasteboard(name: .drag)` in tests. Doing so primes the whole system and makes false positives easy to hit.

A dashed **plus tile**, shown in the empty state and at the end of the row, opens a file picker, so the Shelf is reachable without dragging at all.

## The lock screen

**The island can't be drawn on the lock screen, and that isn't a bug to fix.** When the session locks, `loginwindow` takes the display in a separate security context, and the window server hides every user-session window behind it. No window level is above it. The workarounds that exist (private APIs, injecting into `loginwindow`, disabling SIP) are the same tools used to phish passwords by drawing fake UI next to the real field, so NeoNotch doesn't go near them.

What it does instead:

- **Notifications.** A timer that fires while the Mac is locked posts a system notification, the one supported way to put information on that screen. Notifications need an installed, consistently signed app. An ad-hoc build run from DerivedData may be refused with "Notifications are not allowed for this application".
- **A finished timer doesn't hold the panel open.** It chimes and shows a ring in the closed notch for a few seconds, rather than sitting over your work until you dismiss it.
- **Instant reappearance.** The panel is reordered on `sessionDidBecomeActive`, `didWake`, `screensDidWake` and `com.apple.screenIsUnlocked`, so it is back the moment you are, rather than waiting for the next change to screen parameters.
- **Timers survive.** Countdowns are stored as an end date and the stopwatch as a start date, so both stay exact across lock, sleep and missed ticks.

## Smooth clocks

Timers and the stopwatch are stored as dates, never as accumulating counters, and the views sample them every frame with `TimelineView(.animation)`.

This matters because the stopwatch shows hundredths. Driven by a 0.25 s model tick, it could only ever land on .00, .25, .50 and .75, and visibly stepped. The model's tick now exists only to notice a timer finishing and to refresh the once-a-second label in the closed island, and it publishes only when that whole second actually changes.

The closed island deliberately shows whole seconds even for the stopwatch. Redrawing it means redrawing the notch, and hundredths up there would mean doing that 100 times a second for a number nobody reads that precisely.

## Debugging

### Snapshots

Every panel state renders to PNG without screen recording permission:

```bash
./NeoNotch.app/Contents/MacOS/NeoNotch --snapshot ~/Desktop/shots
```

Snapshots render through a real `NSHostingView` in an offscreen window rather than through `ImageRenderer`. `ImageRenderer` silently skips anything backed by AppKit: sliders come out as yellow placeholder boxes and scroll view content doesn't render at all, so it misrepresents exactly the parts worth checking. Debug builds seed every model with sample data before rendering.

### Tracing

The pointer, hit-test, clipboard and Apple Event paths are invisible from the outside, so they can be traced on demand:

```bash
NEONOTCH_TRACE=1 ./NeoNotch.app/Contents/MacOS/NeoNotch
```

```
[NeoNotch/window] hitTest island centre (380.0, 258.0) -> view (ok)
[NeoNotch/window] hitTest far corner (20.0, 20.0) -> nil (ok: click-through)
[NeoNotch/window] opened, hitRect=(80.0, 70.0, 600.0, 210.0)
[NeoNotch/clipboard] captured text.alignleft "second copied item" from Notes
[NeoNotch/music] broadcast Spotify: playing Midnight City — M83
[NeoNotch/music] showing Spotify playing: Midnight City
```

To get correct permission attribution and logs from an installed copy, launch it through Launch Services:

```bash
open -a /Applications/NeoNotch.app --env NEONOTCH_TRACE=1 --stdout /tmp/neonotch.log --stderr /tmp/neonotch.log
```

When started directly from a shell, macOS attributes Automation prompts to the terminal instead of NeoNotch.

### Self-tests

```bash
./NeoNotch.app/Contents/MacOS/NeoNotch --selftest-widgets
./NeoNotch.app/Contents/MacOS/NeoNotch --selftest-drop /etc/hosts
open -n -W --stdout /tmp/music.txt -a NeoNotch.app --args --selftest-music
```

- `--selftest-widgets` checks the Pomodoro cycle, streaks, bookmark parsing and site-icon discovery, note drafts and the runner's jump, writing only into a throwaway folder.
- `--selftest-drop` reads a file through pasteboards shaped like Finder's, and checks the drag-in-flight truth table.
- `--selftest-music` compiles every AppleScript against the players' real dictionaries and tests the cover lookups. Add `--offline` to skip the network.

## Signing and distribution

Xcode signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`). macOS files every permission under the app's code signature, and an ad-hoc signature is different on every build, so each rebuild looks like a new app and is asked for every permission again. `Scripts/install.sh` re-signs with a stable local certificate when one is available (see the README), so permissions survive rebuilds.

That's fine for running NeoNotch yourself. To distribute builds to other people, you would need a Developer ID certificate, notarisation and the hardened runtime. iCloud sync of notes would also need a signed app with an Apple developer team; until then, notes sync through Reminders instead.
