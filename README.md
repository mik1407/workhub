# WorkHub

macOS container for Gmail, Slack, Google Calendar, Claude, ChatGPT and WhatsApp. Native Swift + WebKit app, no dependencies.

## Build and install

Requirements: macOS 12 or later, Xcode Command Line Tools (`xcode-select --install`).

From the project folder:

```bash
./setup-signing.sh      # once only: creates the "WorkHub Dev" certificate
./build.sh install      # builds, installs to /Applications and launches
./build.sh dmg          # or: creates WorkHub-<version>.dmg to open and drag into Applications
./build.sh test         # runs the logic tests (Tests/ folder) without building the app
swift Tools/make-icon.swift   # rebuilds Resources/AppIcon.icns from Tools/AppIcon.png (or .svg)
```

The build always targets macOS 12 or later, the same minimum version declared in `Info.plist`.

If you open WorkHub from outside Applications (DMG, Downloads, build folder), it offers to move itself there.
From the WorkHub menu you can turn on "Open at Login" (macOS 13 or later).
To keep it in the Dock: right-click the icon > Options > Keep in Dock.

With the certificate the signature stays the same from one build to the next, so macOS doesn't ask again
for keychain or microphone access. The first signed build asks one last time:
enter your Mac password and choose "Always Allow".

Other Macs: the DMG works, but without an Apple Developer ID certificate macOS will show the
"unidentified developer" warning (unblock it in System Settings > Privacy & Security > Open Anyway).

## First launch

1. Allow notifications when macOS asks.
2. Sign in to each service. Gmail and Calendar share the Google session, so signing in once is enough.
3. WhatsApp: scan the QR code with your phone.
4. Turn on desktop notifications in the services that have them off by default:
   Gmail (Settings > General > Desktop notifications) and Calendar (Settings > Notifications).

Sign-ins are kept between launches.

## Usage

| Action | Shortcut |
|---|---|
| Go to service 1–6 | ⌘1 … ⌘6 |
| Open/close the Todos panel | ⌘T (or the icon in the right bar) |
| Open/close the Focus panel | ⌘⇧F (or the stopwatch in the right bar) |
| Reload service / all | ⌘R / ⌘⇧R |
| Reload any service, even one not on screen | right-click its icon > Reload |
| Go back to the service's home page | ⌘⇧H |
| Back / Forward | ⌘[ / ⌘] |
| Hide window (services stay active) | ⌘W |

External links: open in the default browser. ⌘+click forces the browser for internal links too.
Downloads: saved to ~/Downloads.

## Todos

Panel on the right with two lists: Personal and Work.

- Return in the "Add a todo..." field adds to the top of the open list.
- Circle: completes. Completed todos go to the collapsible "N done" section.
- Drag a todo up or down to reorder it; drag it onto the other list's name (at the top) to move it there.
  Esc while dragging cancels.
- Double-click the text: edit (empty text = delete). The × appears on hover.
- Due date: calendar icon on hover (later today, tomorrow at 9, next Monday,
  or a date and time of your choice). The label is red when overdue, blue when due today.
- When a todo is due, a macOS notification arrives (even with WorkHub closed) with "Mark as done" and
  "Remind me in 1 hour"; clicking it opens the panel on that todo. The Todos icon shows how many are overdue.
- Data: `~/Library/Application Support/WorkHub/todos.json`, saved on every change.
  On every launch a copy goes to `todos.json.bak`. If the file can't be read, the app starts with an empty list
  and keeps the original as `todos-broken-<date>.json`.

## Focus

Pomodoro timer in the right bar: 25 minutes of focus, 5 of break, repeating until you press Stop.

- Start focus starts the cycle; Pause/Resume; Skip jumps straight to the next phase; Stop resets.
  Space starts or pauses when the panel is active.
- The timer keeps running with the panel closed: the ring around the stopwatch in the bar shows
  progress (blue = focus, green = break) and the tooltip shows the time left.
- A notification arrives at every phase change; clicking it opens the panel.
- Background sound: plays during focus and fades out during breaks. In the panel you choose the sound
  (outside focus, tapping one plays a 6-second preview), the volume and the on/off switch.
  The sounds have the same perceived loudness and loop seamlessly.
- Sounds live in `~/Library/Application Support/WorkHub/Sounds/` (the project's `Sounds/` folder
  is copied there by `build.sh`). To add more: "Add sounds…" in the panel, or copy m4a, mp3,
  wav or caf files into the folder. They are not included in the app or the DMG.
- Counts the focus sessions completed today (a skipped session doesn't count).

## Settings (⌘,)

- **Services**: add services from the catalog (Gmail, Outlook, Teams, Slack, Notion, Linear, WhatsApp,
  Telegram…) or any website; reorder by dragging (the order also applies to ⌘1–9); change name,
  address, badge and icon; "Sign out and reset data" signs out of the service and deletes its data.
  The same service can be added more than once ("Add another" in the catalog). "Separate sign-in" gives a
  service its own cookies and sign-in, for a second account such as another WhatsApp number (macOS 14 or later);
  without it, all services share one browser session.
  "Separator below" draws a line under the service's icon in the sidebar, to group services; it moves with
  the service when you reorder, and the ⌘1–9 shortcuts keep counting services only.
- **Notifications**: pause for 1 hour or until tomorrow, hidden content, notifications and sound per service,
  silence during focus with the exceptions you choose.
- **Focus**: durations, a long break every N sessions, start the next phase automatically or wait for a click,
  end-of-phase sound.
- **Appearance**: Dark, Light or Automatic theme (follows macOS) for the frame, bars, panels and Settings.
  Services don't change: they always follow the macOS theme.

Everything applies immediately and is saved to `~/Library/Application Support/WorkHub/settings.json`.
If you edit it by hand, a malformed service is ignored (the others are kept); if the whole file can't be read,
the app starts again from the default settings and keeps the original as `settings-broken-<date>.json`.
Other useful files and folders: `icons/` (custom icons), `Sounds/` (Focus sounds), `todos.json`.

Launch at login: WorkHub menu > "Open at Login". To keep it in the Dock: right-click the icon >
Options > Keep in Dock.

## Known limitations

- Slack badge: it reads Slack's DOM, which changes often. If the badge doesn't show up, the selectors are in
  `Sources/Scripts.swift` (`badgeTemplate`, `slack` mode). To inspect the page: Safari > Develop > WorkHub.
- Gmail badge: counts unread messages in the Inbox.
- Calendar, Claude and ChatGPT have no badge, only notifications where available.
- Push notifications for a "sleeping" service (background service worker) aren't supported by WebKit
  in apps: notifications arrive as long as the app is open, even with the window closed.
