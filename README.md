# WorkHub

All your work apps in one window on your Mac: Gmail, Google Calendar, Slack, WhatsApp, ChatGPT, Claude and
any other website you use. It also has a to-do list and a focus timer built in.

- **One window, one place.** Each app has its icon in the sidebar on the left. Click an icon (or press ⌘1, ⌘2…)
  to switch.
- **Notifications and unread counts.** You get Mac notifications from every app, and red badges show
  what's unread, even with the window closed.
- **Todos.** A to-do list with due dates and reminders, always one click away.
- **Focus.** A Pomodoro timer (25 minutes of work, 5 of break) with optional background sounds.
- **Private.** WorkHub has no server and no account of its own. Your sign-ins, settings and todos stay on your Mac.

Works on any Mac with macOS 12 (Monterey) or later.

**Is it safe?** WorkHub shows the same websites you already use, with the same engine as Safari. It has no
server, sends nothing anywhere and has no account of its own. Its code is public, right here on GitHub.

**Keyboard symbols used in this guide:** ⌘ is the Command key, ⇧ is Shift, and keys written together are pressed
at the same time (for example ⌘⇧H = Command + Shift + H).

---

## Install it

There are two ways. **Option 1** is for most people. Use **option 2** only if a colleague gives you the
installer file.

### Option 1: install with a few copy-and-paste commands (10–20 minutes, mostly waiting)

You don't need to know anything about programming: you'll copy four commands into an app called Terminal.

**Open Terminal.** Press ⌘ (Command) + Space, type `Terminal` and press Return. A window with text appears.
For each step below: copy the command (move the mouse over the grey box and click the copy button on its
right), paste it into Terminal with ⌘V and press Return.

**How to tell a step is finished:** Terminal shows a new line ending with `%` and a blinking cursor, ready for
the next command. Until then, just wait. Text scrolling by is normal.

**Step 1: install Apple's developer tools** (free, from Apple, needed once per Mac):

```bash
xcode-select --install
```

A window opens with three buttons: click **Install** (not "Get Xcode"), then **Agree**. Wait until the window
says the software was installed (5–15 minutes), then click **Done**. If Terminal instead says the tools are
already installed, that's fine: go to step 2.

**Step 2: download WorkHub:**

```bash
git clone https://github.com/mik1407/workhub.git ~/WorkHub
```

- If it says `command not found: git`, step 1 hasn't finished yet: wait for its window to say it's done, then
  try again.
- If it says `already exists`, WorkHub was already downloaded (for example on a second try): go to step 3.

**Step 3: let your Mac recognise WorkHub** (once per Mac). This creates a private "signature" that stays on
your Mac, so after each update macOS knows it's still the same WorkHub and doesn't ask for permissions again:

```bash
cd ~/WorkHub && ./setup-signing.sh
```

It's done when you see `Done: certificate "WorkHub Dev" created` (or `already present` if you did it before).

**Step 4: build and install the app:**

```bash
cd ~/WorkHub && ./build.sh install
```

This takes a minute or two. When you see `Installed in /Applications and launched`, WorkHub opens.

During this step macOS may ask: **"codesign wants to access key WorkHub Dev"**. Type your Mac password and
click **Always Allow** (not just "Allow"), so it doesn't ask again.

That's it. You can close Terminal. WorkHub is now in your Applications folder like any other app.

### Option 2: from the installer file a colleague gave you

1. Open the file `WorkHub-<version>.dmg`.
2. Drag **WorkHub** onto the **Applications** folder next to it.
3. Open WorkHub from Applications. The first time, macOS says it can't verify the developer
   (WorkHub isn't distributed through the App Store). To allow it:
   - macOS 15 or later: close the warning, open **System Settings > Privacy & Security**, scroll down to
     "WorkHub was blocked" and click **Open Anyway**.
   - macOS 14 or earlier: right-click WorkHub in Applications, choose **Open**, then **Open** again.
4. The installer doesn't include the focus background sounds: add your own from the Focus panel
   (**Add sounds…**).

The installer file only works on the same kind of Mac as the one it was made on (Apple chip or Intel). To check
yours: Apple menu (top left) > **About This Mac**, look at "Chip". If it doesn't open, use option 1 instead.

---

## First launch

1. **Allow notifications** when macOS asks, otherwise you won't get any.
2. **Sign in** to each app, as you would in a browser. WorkHub starts with Gmail, Slack, Google Calendar,
   Claude, ChatGPT and WhatsApp. Gmail and Google Calendar share the same Google sign-in, so signing in once is
   enough. For **WhatsApp**, scan the QR code with your phone.
   Don't use one of them? Remove it: ⌘, (Settings) > **Services**, select it, click **Remove service** twice.
   You can add others from the same page (**Add service**).
3. **Turn on desktop notifications inside Gmail and Calendar**, which have them off by default:
   Gmail: Settings > General > Desktop notifications. Calendar: Settings > Notifications.
4. Recommended:
   - Start WorkHub automatically: in the menu bar, **WorkHub > Open at Login**.
   - Keep it in the Dock: right-click its icon in the Dock > **Options > Keep in Dock**.

You stay signed in between launches. Closing the window (⌘W) only hides it: notifications keep arriving.
To quit completely, press ⌘Q.

---

## Everyday use

| To… | Do this |
|---|---|
| Switch app | Click its icon in the left sidebar, press ⌘1, ⌘2, … ⌘9, or tap its icon in the Touch Bar (MacBook Pro with Touch Bar) |
| Reload the app you're looking at | ⌘R (all apps: ⌘⇧R) |
| Reload any app, even one not on screen | Right-click its icon in the sidebar > **Reload** |
| Go back to an app's start page | ⌘⇧H |
| Back / Forward | ⌘[ / ⌘] |
| Open or close the to-do list | ⌘T, or the double check mark on the right |
| Open or close the focus timer | ⌘⇧F, or the stopwatch on the right |
| Open Settings | ⌘, (Command + comma), or the gear at the bottom left |
| Hide the window (notifications keep working) | ⌘W |

Links to other websites open in your normal browser. Hold ⌘ while clicking to open any link there.
Downloads go to your Downloads folder.

### Todos

A panel on the right with two lists: **Personal** and **Work**.

- Type in "Add a todo..." and press Return to add it at the top of the list.
- Click the circle to mark it done. Done items go to the "N done" section, which you can collapse.
- Drag a todo to reorder it, or drop it on the other list's name to move it there (Esc cancels).
- Double-click a todo to edit it; delete all its text to remove it. The × appears when you hover over it.
- Web addresses in a todo (starting with `https://`, `http://` or `www.`) become links. Slack links (for example
  a message link copied from Slack) open in WorkHub's Slack; any other link opens in your browser.
- **Due date:** hover over a todo and click the calendar icon (later today, tomorrow at 9, next Monday, or any
  date and time). The date turns blue when it's due today and red when it's overdue.
- At the due time you get a Mac notification, even if WorkHub is closed, with **Mark as done** and
  **Remind me in 1 hour**. The Todos icon shows how many todos are overdue.

### Focus

A Pomodoro timer: 25 minutes of focus, then a 5-minute break, repeating until you press Stop.

- **Start focus** starts it. **Pause/Resume**, **Skip** (jump to the next phase), **Stop**. Space also starts
  and pauses when the panel is open.
- It keeps running with the panel closed: the ring around the stopwatch shows the progress
  (blue = focus, green = break). You get a notification at each change.
- **Background sound** (rain, stream, wind…) plays during focus and fades out during breaks. Choose the sound
  and the volume in the panel. To add your own: **Add sounds…** (m4a, mp3, wav or caf files).
- It counts the focus sessions you complete each day.

---

## Settings (⌘,)

- **Services:** add apps from the list (Gmail, Outlook, Teams, Slack, Notion, Linear, WhatsApp, Telegram…) or
  any website. Drag to change the order (it's also the ⌘1–9 order). Change an app's name, address and icon.
  - **Two accounts of the same app** (for example two WhatsApp numbers or two Gmail accounts): click
    **Add service**, pick the app again (it says "Add another") and sign in with the other account. The new copy
    has **Separate sign-in** turned on, so the two accounts don't mix (needs macOS 14 or later).
  - **Separator below:** draws a line under an app's icon in the sidebar, to group your apps.
  - **Sign out and reset data:** signs you out of that app and deletes its stored data.
- **Notifications:** pause all notifications for an hour or until tomorrow, hide message text (useful when
  sharing your screen), turn notifications and sounds on or off per app, and silence them during focus.
- **Focus:** session lengths, a longer break every few sessions, and whether the next phase starts by itself.
- **Appearance:** Dark, Light or Automatic (follows your Mac). The apps inside keep their own look.

Changes apply immediately.

---

## Update to the latest version

Updating uses Terminal again, with the same one-line command every time. Open Terminal (⌘ Space, type `Terminal`,
Return), paste this and press Return:

```bash
cd ~/WorkHub && git pull && ./build.sh install
```

WorkHub closes and reopens with the new version. Your sign-ins, settings and todos are kept.

## Move to a new Mac

1. Install WorkHub on the new Mac (see [Install it](#install-it)) and quit it (⌘Q).
2. On the old Mac, open Finder, press ⌘⇧G, paste `~/Library/Application Support/WorkHub` and press Return.
3. Copy `settings.json` (your apps and settings), `todos.json` (your todos) and the `icons` folder
   (custom icons) to the same folder on the new Mac.
4. Open WorkHub on the new Mac. You'll need to sign in to the apps again: sign-ins aren't copied.

## Uninstall

1. Quit WorkHub (⌘Q) and drag it from Applications to the Trash.
2. To also delete your settings and todos: in Finder press ⌘⇧G, paste `~/Library/Application Support/WorkHub`
   and move that folder to the Trash.

---

## Something isn't working?

| Problem | What to do |
|---|---|
| I closed the window and it disappeared | Click the WorkHub icon in the Dock: the window comes back. Closing it (⌘W) only hides it. |
| An app shows a blank page | Right-click its icon in the sidebar > **Reload**. WorkHub also retries on its own when the network comes back. |
| No notifications at all | **System Settings > Notifications > WorkHub**: turn on Allow notifications. Also check that notifications aren't paused in WorkHub's Settings > Notifications. |
| No notifications from Gmail or Calendar | Turn them on inside Gmail and Calendar (see [First launch](#first-launch), step 3). |
| Microphone or camera don't work in calls | **System Settings > Privacy & Security > Microphone** (or **Camera**): turn on WorkHub. |
| macOS asks for permissions after every update | Run step 3 of the install once (`./setup-signing.sh`), then update again. |
| "WorkHub can't be opened" (installer file) | See [option 2](#option-2-from-the-installer-file-a-colleague-gave-you), step 3. |
| The Dock still shows an old icon | Open Terminal and run `killall Dock`. |
| The unread count of an app is missing or wrong | Gmail counts unread mail in the Inbox. Slack's count can break when Slack changes its website. Calendar, ChatGPT and Claude have no count. |

Notifications arrive as long as WorkHub is running, even with the window closed. If you quit it (⌘Q), they stop
until you open it again: keep **Open at Login** on.

---

## For developers

Native Swift + WebKit app, no dependencies, built with the Xcode Command Line Tools (no Xcode project).

```bash
./setup-signing.sh      # once per Mac: creates the self-signed "WorkHub Dev" code-signing certificate
./build.sh              # builds WorkHub.app in the project folder
./build.sh install      # builds, replaces /Applications/WorkHub.app and launches it
./build.sh dmg          # builds WorkHub-<version>.dmg with the app and Distribution/How to open WorkHub.txt
./build.sh test         # runs the logic tests (Tests/ folder) without building the app
swift Tools/make-icon.swift   # rebuilds Resources/AppIcon.icns from Tools/AppIcon.png (or .svg)
```

- **Targets:** builds always target macOS 12 or later, the minimum declared in `Info.plist`. `./build.sh dmg`
  tries a universal build (Apple Silicon + Intel). With Command Line Tools that lack the Intel Swift libraries it
  falls back to the current Mac's architecture and says so.
- **Signing:** with the certificate the signature stays the same across builds, so macOS keeps keychain and
  microphone permissions. Without a Developer ID certificate, other Macs show the "unidentified developer"
  warning for DMG builds.
- **Code:** `Sources/` (AppController and its extensions, ServiceController for each web view, Settings, Sidebar,
  FocusTimer, Sounds…), `Resources/` (the HTML pages of the Todos, Focus and Settings panels), `Tests/`.

**Data** (in `~/Library/Application Support/WorkHub/`):

- `settings.json`: services and settings, saved on every change. A malformed service is ignored (the others are
  kept); if the whole file can't be read, the app starts from the defaults and keeps the original as
  `settings-broken-<date>.json`.
- `todos.json`: todos, saved on every change. On every launch a copy goes to `todos.json.bak`; an unreadable file
  is kept as `todos-broken-<date>.json`.
- `icons/`: custom icons (`<id>.png`) and downloaded website icons (`auto/`).
- `Sounds/`: Focus sounds. `build.sh` copies the project's `Sounds/` folder there; they aren't included in the
  app or the DMG.

**Known limitations:**

- Slack badge: it reads Slack's DOM, which changes often. The selectors are in `Sources/Scripts.swift`
  (`badgeTemplate`, `slack` mode). To inspect a page: Safari > Develop > WorkHub.
- Separate sign-in uses per-identifier website data stores, available from macOS 14; on macOS 12–13 every
  service shares one session.
- Push notifications for a "sleeping" service (background service worker) aren't supported by WebKit in apps:
  notifications arrive while the app is running, even with the window closed.
