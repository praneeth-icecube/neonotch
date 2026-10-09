# NeoNotch

A notch companion for macOS, living in a black island pinned to the top of the screen:
a Home dashboard of widgets — music, calendar, bookmarks, quick notes, a Pomodoro timer and
a camera mirror — plus a file shelf with AirDrop, an AI clipboard, timers and games. All of
the AI runs on-device.

No trial, no unlock, no usage counter. It's yours.

## Build and run

```bash
open "NeoNotch.xcodeproj"
```

Then press ⌘R. To build, sign, install into /Applications and relaunch in one go:

```bash
Scripts/install.sh
```

Use the script for the copy you actually run. macOS files every permission — Reminders,
camera, Calendar, Automation — under the app's code signature, and an ad-hoc signature is
different on every build, so each rebuild used to ask for all of them again. The script
signs with one local certificate every time (**NeoNotch Local Signing**, kept in its own
keychain, `Signing/NeoNotch.keychain-db`, not in your login keychain), so a new build is the
same app to macOS and keeps what you allowed. Builds from Xcode are still ad-hoc.

`Signing/` holds a private key, so it is not in this repository. Without it the script
still builds and installs, signed ad-hoc. To keep permissions across rebuilds, create your
own self-signed code-signing certificate named **NeoNotch Local Signing** in a keychain at
`Signing/NeoNotch.keychain-db` (password `neonotch`, or change it in the script).

NeoNotch is an agent app (`LSUIElement`): no Dock icon, no windows of its own. It shows up
as a small notch glyph in the menu bar, with **Open Notch**, **Settings…** and **Quit**.

## This Mac has no notch

`Mac17,5` reports `safeAreaInsets.top == 0` and no `auxiliaryTopLeftArea`, so there is no
camera housing to hug. NeoNotch draws a **virtual notch** instead: a black island the
height of the menu bar, centred at the top of the screen, with the same concave "ears"
a real notch has so it melts into the menu bar rather than sitting on top of it.

Nothing else changes. If you attach a notched external display or move to a notched Mac,
`NotchGeometry` picks up the real cutout automatically and the island snaps to its exact
size. You can force the virtual notch on either kind of machine in Settings → Appearance.

Width and height of the virtual notch are adjustable in Settings.

## What's in it

| Tab | What it does |
| --- | --- |
| **Home** | A dashboard: Music, Timer, Bookmarks, Reminders, Notes, Focus and Mirror side by side (Calendar is one click away in Settings). Timer is Clock-styled: the running timer with pause and cancel, or Recents to start one. Notes writes a new note straight into Apple Notes — no history kept here. Reminders is your Apple Reminders, with + to add one. Show, hide and reorder them in Settings → Home widgets; the panel is exactly as wide as the widgets you keep. See [Home widgets](#home-widgets). |
| **Shelf** | Drop files onto the notch to park them, drag them back out anywhere. Dropped text, images and links are written into a staging folder so they become real, draggable files. Double-click to open, Reveal to show in Finder. The **AirDrop** zone at its head sends whatever you drop on it — or, clicked, everything on the shelf. |
| **Clipboard** | History of what you copy — text, images, files — as a row of cards. Click to copy back, drag straight into another app, pin what you want to keep (pins survive Clear), search. With Apple Intelligence: rephrase, summarise or refine any text card, on-device. Items marked concealed (password managers) are skipped. |
| **Music** | Now playing for Spotify and Apple Music: cover, scrolling title, drag-to-seek scrubber, transport and volume. The closed notch shows the cover and level bars in the album's colour while a song plays. |
| **Timer** | Laid out like Apple's Clock: the running timer's card and Recents down the left, the countdown ring — or an hr/min/sec picker — in the middle, the stopwatch with laps on the right, in Clock's own weights and colours. When a timer finishes it chimes and the closed notch shows "Time's up" with a ring for a few seconds; nothing opens or holds the panel. Timers and the stopwatch running in Apple's Clock app show here too — see [Apple Clock](#apple-clock). |
| **Play** | A chicken runner (Space, ↑ or click to jump, hold ↓ to skid under birds), a reaction test and a Simon-style memory game. Best scores persist. |

Hovering the notch opens the panel, always on Home — never on whichever tab was showing when
it last closed — and moving away closes it. Click the pin to keep it open.
**⌃⌥N** opens and closes it from the keyboard (Settings → General; ⌃⌥⌘N and ⌥⌘\ are the
alternatives). Opened that way it stays open until you press it again.
Dragging a file toward the notch opens it straight onto the Shelf.

## Idle and busy

The closed island has two shapes, and **it only ever grows sideways**:

| | size | notes |
| --- | --- | --- |
| **Idle** | 210 × 30 pt | Just a notch. |
| **Busy** — timer, stopwatch or playback | 320 × 30 pt | Same height, wider. |

30 pt is exactly the menu bar height on this display, so the closed island never reaches
below y30 and never covers the window you are working in. That is the constraint it is
built around; the tabbed panel is the only thing allowed to drop into the workspace, and
only because by then you are looking at it deliberately.

The cost is menu items. macOS lays out the menu bar with **no idea the island exists** — on
a real notched Mac the system reserves the cutout and moves menus around it, but a virtual
notch is just a window drawn on top. On this 1408 pt display, with the screen centre at
x704:

| | width | left edge | vs Chrome's "Help" (~x580) |
| --- | --- | --- | --- |
| Idle | 210 pt | x599 | clear |
| Busy | 320 pt | x544 | covers it |

That is a deliberate trade: staying out of the working area is worth more than the tail of
a menu. Width is adjustable in **Settings → Appearance** if you want it back — every 2 pt
off the width uncovers 1 pt of menu on each side.

## Alignment

The panel is centred on the display's logical frame and rounded to whole points, and the
island is centred inside it with an even width, so it lands on an exact point every time.
On this 1408 pt screen that puts the panel at x104, width 1200 (centre 704 = screen
centre), and the idle island at x495 inside it, width 210 (centre 600 = panel centre).

The **readout is centred too**, which matters more than it sounds. Laying the icon and the
time out as one centred group is the obvious thing and it is wrong: it pushes the number
about 11 pt right of the island's centre line. The number is what the eye lines up against
the camera, so the black then reads as extending too far left even though the pill is
centred to the pixel. `CollapsedView` centres the readout in a `ZStack` and gives the icon
a mirrored gutter on the right — filled with a progress ring or level bars, so the pill is
balanced by weight and not only by geometry.

If it still reads as off-centre, that is usually the laptop's panel not sitting perfectly
centred inside its lid — screen-centred and case-centred are not the same thing. **Settings
→ Appearance → Alignment** nudges it ±60 pt for exactly that case.

Careful measuring against the case: this display is 11.00 inches wide at 128 pt/inch, so a
centred 210 pt island leaves 4.68 inches of screen on each side. Gaps that sum to more than
11.00 inches are picking up bezel.

## How the window works

The panel is a borderless, non-activating `NSPanel` at `.screenSaver` level, so it draws
above the menu bar and above full-screen windows. It is a fixed 1200×280 — wide enough for
Home with every widget on, plus its shadow — and always transparent except for the island
itself.

Every tab opens at the same width, Home's. Hovering a tab switches to it, so a panel that
resized per tab would slide the tab strip out from under the pointer, and the pointer
would land on another tab and switch again. Tabs that do not want the width — the player,
the timers, Settings — centre their content instead.

The interesting part is click-through. `PassthroughHostingView` overrides `hitTest(_:)` and
returns `nil` for any point outside the island's current rect, so clicks in the transparent
area fall through to the menu bar and whatever app is underneath. The rect is kept in
window coordinates (bottom-left origin) to avoid flipped-coordinate guesswork.

Pointer tracking polls `NSEvent.mouseLocation` at 10 Hz as the primary signal, with
`NSEvent` monitors as a zero-latency accelerator. The poll is what makes it reliable:
move events do not reach a background agent in every situation — over another app's
full-screen surface, mid-drag-session, or when the pointer is warped rather than moved.

Two edge cases the island depends on, both easy to get wrong invisibly:

- `PassthroughHostingView` returns zero `safeAreaInsets`. The panel deliberately overlaps
  the menu bar and AppKit answers that by insetting the hosting view, which pushes the
  island down, leaves dead space above it, and makes the top of the pill unclickable while
  still looking solid.
- The hover rect is padded 8 pt **above** the island. Its top edge is the screen's top
  edge, and `CGRect.contains` treats maxY as exclusive — so without that padding, the exact
  row of pixels the pointer lands on when you throw it at the top of the screen is the one
  row that does not register.

While something is running full-screen on the display, the island steps out of the way.

## Music

The first version of the Music tab never showed anything, from either player, and the
reason is worth recording: its AppleScript kept the player state in a variable called
`st`, and **`st` is a reserved word in AppleScript** (the ordinal suffix, as in `1st`). The
script failed to compile, every query died before it reached the player, and the error was
swallowed into "Nothing playing". Every script variable now carries an `nn` prefix, and
`--selftest-music` compiles each script against the player's real dictionary so a typo
like that fails a check instead of a listening session.

Now-playing arrives on two channels:

- **Broadcasts.** Spotify posts `com.spotify.client.PlaybackStateChanged` and Music posts
  `com.apple.Music.playerInfo` on every play, pause and track change. Receiving them needs
  **no permission** and they arrive instantly, so a song shows up the moment it starts even
  if Automation was never granted. They are registered with `.deliverImmediately`: AppKit
  suspends distributed notifications while an app is inactive, and an agent app is inactive
  nearly all the time, so without it every broadcast would wait for your next click.
- **Apple Events.** Controls, volume, Music's position and the embedded cover need
  Automation permission. With it, a 2.5 s poll keeps position and volume honest; the
  scrubber itself is extrapolated from an anchored clock, so it moves smoothly without the
  model publishing every frame.

Durations are the classic trap: both broadcasts report milliseconds, Spotify's Apple Events
report milliseconds, and Music's Apple Events report seconds.

**Permission.** The first time a player is seen running, NeoNotch asks macOS once (the
standard "NeoNotch wants access to control Spotify" dialog). Declined, the player still
shows up from broadcasts; the controls swap the volume slider for a **Turn on in Settings**
pill that opens Privacy & Security → Automation, and access switched on there is picked up
within ten seconds without a relaunch. Pressing a control before access was ever asked
shows the dialog and then performs the press.

Because the app is ad-hoc signed, every rebuild is a new app as far as macOS is concerned,
so expect the dialog again after rebuilding.

**Covers** come from the most exact source available: the player itself over Apple Events,
then — needing no permission — Spotify's public oEmbed endpoint for Spotify tracks, or the
iTunes Search API (matched on artist) for Apple Music. Those two send the track's ID, or its
artist and album, to the company whose catalogue it is already in. The cover's dominant
colour tints the level bars; a near-greyscale cover stays neutral rather than inventing one.

When playback pauses, the closed notch keeps the live activity for 2.5 s with flat bars,
so skipping a track does not make the island jump in and out.

```bash
open -n -W --stdout /tmp/music.txt -a NeoNotch.app --args --selftest-music
```

Launch the self-test through `open` as above: macOS files Automation permission under
whichever app launched a process, so started from a terminal the permission lines describe
the terminal's access rather than NeoNotch's. `--offline` skips the two cover lookups.

## Apple Clock

Timers and the stopwatch you start in Clock show up in the notch within a second, with
nothing to set up. Clock keeps them with its daemon, `mobiletimerd`, in a preferences domain
(`com.apple.mobiletimerd`) any app of yours can read: each timer is saved with its fire
time — a date while it runs, time left otherwise — and the stopwatch with its state, start
date and offset. `ClockBridge` polls it once a second and `TimerModel` follows what it finds:
paused, resumed or stopped in Clock, it follows here. NeoNotch's own timer keeps the notch
while it runs. A Clock timer that runs out gets the notch's ring but not its chime; Clock
sounds its own.

Going the other way is harder, and this is why:

- The daemon only talks to Apple-signed apps (Clock carries the private
  `com.apple.private.mobiletimerd` entitlement), and Clock has no AppleScript.
- Clock's actions for Siri (`TimerAppIntents`, `StopwatchAppIntents`) are Siri-only.
- `MobileTimerSupport` does give Shortcuts real Clock actions — Start, Pause, Resume and
  Cancel Timer; Start, Stop, Lap and Reset Stopwatch; Add and Remove City.
- A ready-made shortcut file cannot be signed here: `shortcuts sign` needs iCloud, which
  this Mac is not signed into.

So NeoNotch runs shortcuts you make once, found by name and run with `/usr/bin/shortcuts`.
Each holds one Clock action and is named after it — **NeoNotch Start Timer**, **NeoNotch
Cancel Timer**, **NeoNotch Start Stopwatch** and so on; the full list, with a tick for each
one found, is in Settings → Apple Clock. In Start Timer, the duration is Shortcut Input, in
minutes. Every one is optional: whatever exists is used, controls without a shortcut offer
**Open Clock** instead, and without Start Timer a timer started here is NeoNotch's own.
A timer sent to Clock shows at once and is swapped for Clock's own when Clock reports it —
and if Clock never does, it stays in NeoNotch so it still rings.

World clocks are out of reach: Clock keeps them in a protected group container
(`group.com.apple.mobiletimerd`) that no other app may read.

## Look

Content sits straight on the black, with no cards, and sections are split by hairlines.
Hierarchy comes from white at a few fixed opacities (`NotchTheme`) rather than from boxes,
which is what keeps a panel this small from reading as clutter. Tabs are icons only, with
the title as a tooltip. While a song plays, the Music tab's icon becomes level bars in the
cover's colour, so you can see it is playing from any tab.

The tabs are 40 pt wide and 12 pt apart, and hovering one switches to it only once the
pointer has rested there for 0.15 s; a click switches at once. They used to be 2 pt apart
and switch on contact, so the slightest overshoot — or a diagonal move down into the
panel — landed on the neighbour and switched to it: aiming for Clipboard got you Music. The
icon brightens the moment the pointer arrives, so the wait never reads as lag.

## Home widgets

- **Music** — the compact player from the Music tab.
- **Calendar** — the day's events from the Calendar app with their calendar's colour down
  the side, and yesterday / today / tomorrow along the bottom. Click an event to open it
  in Calendar. ✦ writes a **daily brief** of the day with Apple Intelligence. Read-only.
- **Bookmarks** — launch sites and apps in one click. `+` takes an address or an app;
  right-click to remove or reorder. Site icons come from the sites themselves
  (`apple-touch-icon`, `icon`, `/favicon.ico`) — never a third-party favicon service, which
  would learn every site you keep — and are cached on disk.
- **Notes** — "What's on your mind?", a colour per note, a circle to tick it off. ✦
  rephrases what you are writing. The note you are typing lives in a draft, so the panel
  closing mid-sentence loses nothing, and the panel stays open while you type. **Sync with
  Reminders** turns the list into your Reminders, both ways: add, edit, tick off or delete
  here or in Reminders. Every list shows; new ones from the notch go to your default list.
  Open reminders are listed, plus those finished today,
  so a tick does not make a row vanish under the pointer. The colour bar stays NeoNotch's
  own, since Reminders has no colour per item. Until you connect, notes stay in
  `notes.json`, and they are still there if you ever disconnect.
- **Focus** — Pomodoro: focus sessions, short breaks, a long break after the last session
  of the cycle, a sound and a notification at each change, and a daily streak. Lengths,
  sessions per cycle and auto-start are in Settings → Focus. While it runs, the closed
  notch shows the time left and a ring.
- **Mirror** — the camera as a round mirror. It starts when clicked and stops the moment it
  leaves the screen, so the camera light never stays on behind your back.

The header carries a **battery capsule** — a battery drawn to the real level —
and plugging in shows the charge in the closed notch for three seconds. Below 20% and 10%
on battery you get a red warning.

**Apple Intelligence** runs through the Foundation Models framework (macOS 26 and later):
everything is on-device, and where it is unavailable the ✦ buttons simply do not appear.
Settings → Apple Intelligence says which.

Notes, bookmarks, focus history and clipboard history are JSON files in
`~/Library/Application Support/NeoNotch`. Notes do not sync through iCloud, because iCloud
needs a signed app with an Apple developer team and this one is
signed ad-hoc — but connected to Reminders, the notes sync wherever Reminders does.

```bash
NeoNotch.app/Contents/MacOS/NeoNotch --selftest-widgets
```

checks the logic behind them — the Pomodoro cycle, streaks, bookmark parsing and site-icon
discovery, notes drafts, the runner's jump — writing only into a throwaway folder.

## Tracing

The pointer, hit-test, clipboard and Apple Event paths are invisible from the outside, so
they can be traced on demand:

```bash
NEONOTCH_TRACE=1 ./NeoNotch.app/Contents/MacOS/NeoNotch
```

```
[NeoNotch/window] hitTest island centre (380.0, 258.0) -> view (ok)
[NeoNotch/window] hitTest far corner (20.0, 20.0) -> nil (ok: click-through)
[NeoNotch/window] opened, hitRect=(80.0, 70.0, 600.0, 210.0)
[NeoNotch/clipboard] captured text.alignleft "second copied item" from Notes
[NeoNotch/music] broadcast Spotify: playing Mr. Brightside — The Killers
[NeoNotch/music] showing Spotify playing: Mr. Brightside
```

## Snapshots

Every panel state renders to PNG without needing screen-recording permission:

```bash
./NeoNotch.app/Contents/MacOS/NeoNotch --snapshot ~/Desktop/shots
```

This renders through a real `NSHostingView` in an offscreen window rather than through
`ImageRenderer`. `ImageRenderer` silently skips anything AppKit-backed — sliders come out
as yellow placeholder boxes and scroll view content does not render at all — so it lies
about exactly the parts worth checking.

## Drops

Drops are handled in AppKit, on `PassthroughHostingView`, not with SwiftUI's `onDrop`.

That is not a style preference. SwiftUI normalises the type list you give it: asking for
`[.fileURL, .image, .pdf, .text, .url, .item]` registered exactly two types with AppKit —
`public.data` and `public.item` — so **`public.file-url` was never registered at all**, and
that is the type Finder puts on the pasteboard when you drag a file. The notch silently
refused every file, with no error anywhere. `registeredDraggedTypes` is what exposed it.

Registering explicitly now covers `public.file-url`, `NXFileContentsPboardType`, plain text,
TIFF, PNG, PDF, URL, RTF and HTML, and `ShelfModel.accept(pasteboard:)` reads the drop
straight off the pasteboard in priority order with no type negotiation in between.

### Catching the drag early

Waiting for the drag to actually reach the drop target is too late — that target is the
210 × 30 strip in the menu bar, and you have to be on it before anything reacts.

So the pointer poll watches for an incoming drag and snaps the panel open onto the Shelf
from a **610 × 160 pt** approach zone (43% of the screen width, top of the display),
whatever tab was last open, with no hover delay and a faster spring. By the time the drag
arrives the whole panel is the drop target.

There is no public "is a drag happening anywhere" API, so `NotchDragTypes.isDragInFlight`
infers it — and the obvious inference is wrong in a way worth recording.

"Button held, and the drag pasteboard offers a type we accept" seems right, but **the drag
pasteboard keeps its contents after the drag ends**. Once anything had ever been dragged,
every ordinary click matched, and the notch flew open on the Shelf for no visible reason.

What actually marks a drag is that the pasteboard gets *rewritten* when one starts. So the
baseline change count is captured whenever no button is held, and a drag counts as in
flight only once that count moves while a button is down. `NotchDragTypes.dragInFlight` is
split out as a pure function and its truth table is covered by `--selftest-drop`, the stale
pasteboard case included — that regression should fail a check, not a screen recording.

Note for anyone writing tests here: never write to `NSPasteboard(name: .drag)`. Doing so
primes the whole system, and it is what made the false positives so easy to hit.

There is also a dashed **plus tile** — in the empty state and at the end of the row — which
opens a file picker, so the shelf is reachable without dragging at all.

`--selftest-drop` exercises the read path against pasteboards shaped exactly like Finder's:

```bash
./NeoNotch.app/Contents/MacOS/NeoNotch --selftest-drop /etc/hosts
```

## Shape

`NotchShape` is modelled on the MacBook Pro camera housing. Two things make it read as a
notch rather than as a floating pill:

- **True circular fillets.** Every corner is built with `addArc(tangent1End:tangent2End:)`,
  which is tangent to both edges by construction. The first version used quadratic curves
  with the control point parked on the corner — close to a circle, but not one, and it
  looked soft and inflated.
- **The right ratios.** The real notch is ~37 pt tall with roughly a 10 pt bottom radius
  and a 5–6 pt ear, so the bottom corner is about a quarter of the height and the ear about
  a sixth. `NotchShape.macBookPro(height:)` scales those to whatever height the island is.
  The shape is squarer than it looks from memory; the old 14 pt bottom radius on a 31 pt
  island was nearly half the height.

The closed island uses these ratios. The open panel keeps its own softer radii, because at
that point it is a panel and not a notch.

One difference remains, deliberately: a real notch is about 172 × 37 pt (≈4.6∶1) while the
idle island here is 210 × 30 (7∶1), so it is wider and shorter. Height is pinned to the
menu bar so the island never enters the workspace, and 37 pt would hang 7 pt below it.

## The lock screen

**The island cannot be drawn on the lock screen, and that is not a bug to be fixed.** When
the session locks, `loginwindow` takes the display in a separate security context and the
window server hides every user-session window behind it. There is no window level above it.
The workarounds that exist — private APIs, injecting into `loginwindow`, disabling SIP —
are the same primitives used to phish passwords by drawing fake UI next to the real field,
so this app does not go near them.

What it does instead:

- **Notifications.** A timer that fires while you are locked posts a system notification,
  which is the one supported way to put information on that screen. **This currently fails
  on this machine** — `UNUserNotificationCenter` returns "Notifications are not allowed for
  this application", because the app is ad-hoc signed and launched from a DerivedData path
  rather than installed and signed. The sound and the held-open panel still work. Moving
  the app to `/Applications` and signing it properly is what fixes this.
- **A finished timer does not hold the panel open.** It used to, and the panel then sat
  over your work until you found Dismiss. Now it chimes and rings in the closed notch for
  a few seconds; the notification above is what reaches you on the lock screen.
- **Instant re-assert.** The panel is re-ordered in on `sessionDidBecomeActive`,
  `didWake`, `screensDidWake` and `com.apple.screenIsUnlocked`, so it is back the moment
  you are, rather than waiting for the next screen-parameters change.
- **Timers survive.** Countdowns are stored as an end date and the stopwatch as a start
  date, so both stay exact across lock, sleep and missed ticks.

## Smooth clocks

Timers and the stopwatch are stored as dates, never as accumulating counters, and the
views sample them per frame with `TimelineView(.animation)`.

This matters: the stopwatch shows hundredths, and it used to be driven by the model's
0.25 s tick, so it could only ever land on .00, .25, .50 and .75 — visibly stepping. The
model's tick now exists only to notice a timer finishing and to refresh the once-a-second
label in the closed island, and it publishes only when that whole second actually changes
rather than on every tick.

The closed island deliberately shows whole seconds even for the stopwatch: redrawing it
means redrawing the notch, and hundredths up there would mean doing that 100 times a
second for a number you are not reading that precisely.

## Permissions

- **Automation** — the Music tab's controls drive Apple Music and Spotify over Apple
  Events, so macOS asks once per app. Seeing what is playing does not need it (see
  [Music](#music)). The private now-playing APIs are entitlement-gated on current macOS,
  which is why this goes through the players directly.
- **Calendar** — Full Access to events, asked only when you press Allow in the Calendar
  widget. NeoNotch only reads.
- **Reminders** — Full Access, asked only when you press Sync with Reminders in the Notes
  widget. NeoNotch adds, edits, ticks off and deletes reminders when you do that in the notch.
- **Camera** — asked the first time you open the Mirror.
- **Notifications** — for timers and focus sessions ending.
- **Network** — album covers (Spotify's oEmbed, the iTunes Search API) and bookmark icons,
  from the sites themselves.
- **No sandbox**, so the shelf can reference files wherever they live.
- **No accessibility permission needed** — not even for the keyboard shortcut, which uses
  Carbon's `RegisterEventHotKey`.

## State of things

Verified end to end on this machine: hover-to-open and close, hit-test passthrough,
clipboard capture, shelf rendering with real file icons, and every tab's layout.

Music, verified against live Spotify on this machine: a real session was picked up from
broadcasts before any permission existed, the Automation dialog appeared and was granted,
track changes and a pause pressed in the notch went through, and the Apple Events query
answered with the right title, a duration correctly converted from milliseconds, and
volume. Spotify's real broadcast carries `Track ID`, `Duration` (ms) and
`Playback Position` (s), exactly as parsed. Apple Music has only been exercised with
broadcasts shaped like its own and by compiling its scripts; it was not playing here.

Home widgets: every state renders in `--snapshot`, and `--selftest-widgets` and
`--selftest-music` pass. Apple Intelligence answered a real on-device request here. **Not yet
exercised live:** the Calendar widget against real events (access has not been granted on
this Mac), the camera preview, an actual AirDrop send, a press of the keyboard shortcut,
and typing into a note inside the panel. Those need a person at the keyboard.

Xcode signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`), since there is no developer certificate on
this machine; `Scripts/install.sh` re-signs with the local certificate so permissions
survive rebuilds (see [Build and run](#build-and-run)). That is fine for running it
yourself. To share it with anyone else you would need a Developer ID certificate and
notarisation, and hardened runtime turned back on.
