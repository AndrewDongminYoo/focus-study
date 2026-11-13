# Monitor timing in DEBUG builds

Date: 2026-11-13.
Status: design for approval.
Source: [issue #113](https://github.com/AndrewDongminYoo/focus-study/issues/113), and [issue #119](https://github.com/AndrewDongminYoo/focus-study/issues/119) for the slow focus overwrites.
This document amends the [registration marker design](2026-11-10-registration-marker-design.md) and the [stop marker design](2026-11-10-stop-marker-design.md) only where [Superseded lines](#superseded-lines) says so.
It keeps the process-lock rule: lock sections stay synchronous, with no `await`, UI wait or actor hop inside the lock.
This document changes no code.

## Contract

Decided on 2026-11-13:

1. A DEBUG build of the Monitor extension can time each callback: the access read, each lock attempt, the registration-marker read, the lock-hold time of the section, and each Screen Time call inside the section.
2. Every line of the timing is behind `#if DEBUG`. A Release build of the Monitor contains none of it.
3. The app turns the timing on with a flag file in the App Group container, which it writes only when it runs with `--screen-time-diagnostics`. A Monitor callback reads the flag before it times anything, and a missing, unreadable or stale flag means no timing.
4. Synthetic UI fixtures (`--ui-testing`) never write, read or remove the flag.
5. The lines go to the unified log with one subsystem and one category. The app console of `--screen-time-diagnostics` stays as it is.
6. A line carries the callback kind and a short activity kind. It never carries an activity name, a session or revision UUID, a selection token, an app name or a domain.
7. The timing changes no behavior: no extra lock attempt, no extra Screen Time call, no wait, and the flag read happens outside the lock.

Out of scope: the implementation, the device run, any change to the lock wait or the retry budget, and a decision on the cause of #119.

## Evidence

- `Monitor/FocusMonitor.swift` logs nothing today; its `catch` says "No sensitive logging".
- Issue #113 states that the Monitor extension gets no launch arguments, so `--screen-time-diagnostics` cannot turn on a line there.
- `FocusMonitor.reconcile` calls `SessionControl.handleCallbackRetryingLock` with `authorized: { ScreenTimeAccess.current() }`, and the engine calls that closure once before each lock attempt.
  Off the main thread, `ScreenTimeAccess.current()` reads through `DispatchQueue.main.sync` (`Integration/ScreenTimeAdapters.swift`).
  `[UNCERTAIN]` On which thread the extension delivers a callback; the [access-state design](2026-11-11-access-state-design.md#reading-on-the-main-queue) leaves the same point open.
- The engine makes attempt 0 without a wait, then up to 5 attempts that wait up to 0.25 s with 4 pauses of 0.25 s, and it reads the registration marker only after a `lockTimeout` (`Shared/SessionControl.swift`).
- `FocusMonitor` builds its engine from protocols of `Shared/`: `ControlStore`, `MonitoringClient`, `ShieldClient`, `BreakSelectionStore` and `EverydayLayerStore`. Every Screen Time call of a section goes through one of them.
- `project.yml`: the Monitor target compiles `Monitor`, `Shared`, `Integration` and part of `Activity`, and `Configuration/Monitor.entitlements` lists the App Group `group.kr.donminzzi.focusStudy`. `GroupConfiguration.directory()` returns the directory `SessionControl/` of that container for the app and the Monitor.
- `App/FocusRuntime.swift`: `process()` builds the fixture runtime when the arguments contain `--ui-testing` and the real runtime otherwise, and `real()` reads `--screen-time-diagnostics` inside `#if DEBUG`. A background launch for the Focus filter has no launch arguments and builds the real runtime.
- The app console lines (`SCREEN_TIME_TIMING`, `START_LATENCY`, `BREAK_LATENCY`, `END_LATENCY`) are written with `NSLog` and hold an operation or action name and a time. None of them holds a session id, so no shortened form of one exists.
- `Integration/DeviceDiagnostics.swift` (all `#if DEBUG`) has `ScreenTimeOperation`, `measureScreenTime` and `DiagnosticMonitoring`, and the Monitor target compiles that file.
- Issue #119: on 2026-11-11, a focus registration that overwrote a registered focus activity took 289.9 to 300.3 ms (break request or resume) or 508.3 to 510.1 ms (break start) in the app, and no Monitor-side line exists to show where that time goes.
- The stop marker design leaves the lock-hold time of Monitor sections unverified ([Physical-device verification](2026-11-10-stop-marker-design.md#physical-device-verification)).

Apple's article "Generating Log Messages from Your Code" (documentation JSON, read on 2026-11-13):

> By default, the system doesn't redact integer, floating-point and Boolean values, but it does redact the contents of dynamic strings and complex dynamic objects.

The same article's table says that a notice (default) message is persisted to disk "Yes, up to a storage limit", and that a debug message is not.

`man log` on the Mac (macOS, Darwin 25.6.0, read on 2026-11-13): `log collect` has `--device`, `--device-name` and `--device-udid` ("Collect system logs from paired device"), `log show` reads an archive with `--archive` and shows "only default level messages unless --info and/or --debug are specified", and `log stream` has no device option.
So `log stream` on the Mac reads the Mac's own log, not the log of an attached iPhone.
`[UNCERTAIN]` Whether Console on the Mac shows the messages of an extension on an attached iPhone while they arrive; Apple's article "Viewing Log Messages" (read on 2026-11-13) names Console and the `log` tool, but says nothing about a connected device.
`[UNCERTAIN]` Whether `log collect --device-udid` works for this device and iOS version, and for how long the device keeps the messages.

## Design

### Diagnostics flag

The flag is the file `monitor-timing.json` in the App Group directory `SessionControl/`, next to `control.json`.

| Field           | Type   | Meaning                                     |
| --------------- | ------ | ------------------------------------------- |
| `schemaVersion` | `Int`  | `1`.                                        |
| `writtenAt`     | `Date` | The wall clock when the app wrote the file. |

The file holds nothing else.

- **Write.** A DEBUG app writes the flag when it builds the real runtime with `--screen-time-diagnostics`, with the write options of `control.json`. Each such launch writes it again.
- **Remove.** A DEBUG app removes the flag when it builds the real runtime without the argument. This includes a background launch for the Focus filter, which has no launch arguments; timing then stops until the next launch with the argument.
- A write or a removal that fails does not stop the launch. A failed write means no timing, and a failed removal leaves a flag that goes stale.
- **Read.** A DEBUG Monitor callback reads the flag once, at its start, before the access read and outside any lock. It does not cache the result, so a removal takes effect at the next callback.
- **Valid.** The flag is on only when the file decodes, `schemaVersion` is `1`, and `0 <= now - writtenAt <= 24 hours`. Every other case (missing, unreadable, another version, older, or written in the future) means no timing.
- The fixture runtime never builds the real runtime, so `--ui-testing` neither writes nor removes the flag, and it starts no real monitoring, so no Monitor callback reads the flag for it. A flag that an earlier diagnostics run left stays until the next launch of the real runtime without the argument, or until it is stale.
- A Release app never writes or removes the flag, and a Release Monitor never reads it. A flag that a DEBUG build left before a Release install is a file with a version and a time that nothing reads.

### What a callback times

The timing uses DEBUG wrappers around the values that `FocusMonitor` already passes to the engine, so `Shared/` does not change.
With a valid flag, the callback builds its engine with the wrappers; without one, it builds the engine of today and emits nothing.
Every duration is measured on `ProcessInfo.processInfo.systemUptime`, as `measureScreenTime` does.

| Step      | What it times                                                                                                      | Wrapper                   |
| --------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------- |
| `begin`   | The flag read                                                                                                      | none                      |
| `access`  | One `ScreenTimeAccess.current()` read; the engine makes one before each lock attempt                               | the `authorized` closure  |
| `lock`    | One lock attempt, from the call of `withExclusiveAccess` to the start of the section body, or to its `lockTimeout` | `ControlStore`            |
| `marker`  | One marker read after a busy lock attempt                                                                          | `RegistrationMarkerStore` |
| `call`    | One Screen Time call inside the section                                                                            | see the table below       |
| `section` | The section body, from its start to its return or throw                                                            | `ControlStore`            |
| `end`     | The whole callback, from the flag read to the return or throw of `handleCallbackRetryingLock`                      | none                      |

The `section` time is the lock-hold time without two small parts that the store runs outside the body: the delete of a leftover marker before the body, and the unlock after it.

| `op`                                                                                     | Engine call that it times                                                                   |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `register`, `register_break`, `register_everyday`, `stop`, `stop_break`, `stop_everyday` | The `MonitoringClient` call of the same name, as `DiagnosticMonitoring` times it in the app |
| `apply_shield`                                                                           | `BreakSelectionStore.restoreShield(id:)`: the read of the copy, the apply and the match     |
| `clear_shield`                                                                           | `ShieldClient.clear()`                                                                      |
| `apply_everyday`                                                                         | `EverydayLayerStore.applyStored()`: the read of the file, the apply and the match           |
| `clear_everyday`                                                                         | `EverydayLayerStore.clearShield()`                                                          |

- The engine puts its marker wrapper (`MarkedMonitoring`) around the client that it gets, so a `register` or `stop` time does not include the marker write and delete.
- Reads (`registeredBreaks`, `isRegistered(id:)`, `registeredEveryday`, `storeMatches()`, `hasShield`) and file work have no line of their own. They are the rest of `hold_ms` after the `call` lines.
- The Live Activity read after the callback (`synchronizeActivity`) is not timed, and it emits no line.

### Lines

The Monitor writes each line with `Logger(subsystem: "kr.donminzzi.focusStudy.monitor", category: "timing")` at the notice (default) level, so that the device keeps it and `log show` prints it without `--info`.
Every interpolated string is one of the fixed values below and is marked public; no activity name reaches the logger.

```plaintext
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=begin flag_ms=<ms>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=access ms=<ms> state=<approved|denied|unknown>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=lock attempt=<0-5> wait_ms=<ms> result=<acquired|busy>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=marker ms=<ms> marker=<none|register|stop> result=<skip|continue>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=call op=<op> ms=<ms>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=section hold_ms=<ms>
MONITOR_TIMING cb=<n> kind=<kind> activity=<activity> step=end total_ms=<ms> result=<ran|skipped|lock_timeout|error>
```

- `cb` is a counter of timed callbacks in this extension process, from 1. It joins the lines of one callback, together with the process id that the log tools print.
- `kind` is `didStart`, `didEnd` or `willEndWarning`.
- `activity` is `focus` for `focus.<UUID>`, `break` for `focus.<UUID>.break.<n>`, `everyday` for `everyday.<UUID>.<part>`, and `other` for every other name, such as `probe.*`.
- Every time is in milliseconds with 3 decimals, as in the app console lines.
- `marker` is what the read returned before the freshness check. `result=skip` means that the callback returned after this read without a section; every other case is `continue`. The wrapper takes this from what the engine does next, and it does not evaluate the skip rule again.
- `result` of `end`: `ran` when a section body ran, `skipped` when the callback returned without one, `lock_timeout` when the retries ran out, and `error` for every other throw.
- The `begin`, `access`, busy `lock` and `end` lines are emitted when their step ends, and a `marker` line when the engine's next step shows its result; all of them are outside the lock.
- The lines of an acquired lock (`lock` with `acquired`, each `call`, and `section`) are kept in memory during the section and emitted right after the lock is released, so no log call runs inside the lock.
  A callback whose process ends inside a section shows `begin` and no `end`.

### Cost

| Build and flag       | Added to one callback                                                                                                                                                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Release              | Nothing. The code is not compiled.                                                                                                                                                                                 |
| DEBUG, no valid flag | One read of a small file before the access read, outside the lock. No wrapper and no line.                                                                                                                         |
| DEBUG, valid flag    | That read, and one log call for each line outside the lock. Inside the lock: two uptime reads and one in-memory record for each `call` and for the section, and one forwarded call for each wrapped protocol call. |

The wrappers forward each call once and add no lock attempt, no Screen Time call, no pause and no file write.
The log calls between lock attempts make a callback with timing slightly longer than one without it; `total_ms` includes them.

### Release and fixtures

- The flag type, the wrappers, the logger and their call sites are inside `#if DEBUG`, in `Monitor/`, `Integration/` and `App/`.
- The flag write and removal sit in `FocusRuntime.real()`, which a fixture launch never calls.
- `docs/notes/development-launch-arguments.md` gets the flag, the lines and the read commands in the implementation PR.

### Reading the lines

The predicate is the same for every tool:

```plaintext
subsystem == "kr.donminzzi.focusStudy.monitor" && category == "timing"
```

After a run, with the device attached to the Mac:

```bash
log collect --device-udid <UDID> --last 30m --output monitor-timing.logarchive
log show --archive monitor-timing.logarchive --predicate 'subsystem == "kr.donminzzi.focusStudy.monitor" && category == "timing"'
```

Console on the Mac, with the device selected and the same subsystem and category as its filter, is the live view, if it shows these messages (see the `[UNCERTAIN]` lines in [Evidence](#evidence)).
`log stream` with this predicate reads only the Mac's own log, so it is not a route to the device.
The archive stays out of the repository.

## Alternatives considered

**Timing in every DEBUG build, without a flag.** It needs no file, but every Debug install would log on every callback, also in daily use and during synthetic runs on a device that has real activities registered.
It is rejected because the existing diagnostics are opt-in for each launch.

**A flag in the App Group `UserDefaults`.** It is rejected because the control files of the app and the Monitor are files in `SessionControl/`, and one more file there needs no new reader pattern.

**Lines in an App Group file that the app prints to its console.** It is rejected because each line would be a file write in the callback, and the app would need a reader and a cleanup for it.

**A log call for each line at the moment of its step, also inside the lock.** A callback that never returns would show more lines, but each log call would count in the lock-hold time that the line reports.
It is rejected; the `begin` line without an `end` line already shows such a callback.

**An observer argument on `handleCallbackRetryingLock`.** The engine could report its own steps, but the argument would be in `Shared/` and in the Release build.
It is rejected because the wrappers see the same steps from outside.

## Superseded lines

This change adds a dated reconciliation line directly below each of these lines, and it does not rewrite them:

- Registration marker design, [What does not change](2026-11-10-registration-marker-design.md#what-does-not-change): "The marker is not DEBUG-only; the timing logs stay DEBUG-only, and the Monitor adds no log."
- Stop marker design, [Physical-device verification](2026-11-10-stop-marker-design.md#physical-device-verification), acceptance: "Monitor sections have no timing line, so their lock-hold time stays unverified."

## Physical-device verification

This section is a plan for a later run, not a result.
Record each result in the [device matrix](../notes/screen-time-device-matrix.md), in issue #113 and, for step 4, in issue #119.
Each install and each run that applies real restrictions needs its own explicit approval.
Simulator results and synthetic monitoring cannot establish any of these results.

1. Build a signed Debug build of the implementation commit, and launch it with `--screen-time-diagnostics` on the iPhone 16 Pro of the 2026-11-11 run, or record the device and iOS version used.
2. Start a session. Collect the log as in [Reading the lines](#reading-the-lines), and confirm that at least one `MONITOR_TIMING` line arrived before going on.
3. Request a break, let the break start, put the app in the background, and wait until the break warning re-blocks, about 3 minutes after the break start. Record every line of the `kind=willEndWarning activity=break` callback: its `section hold_ms` and its `call` lines.
4. In the same session, make a focus overwrite with the app in front (a break request, and a resume). For each one, record the `access`, `lock`, `marker` and `end` lines of the callbacks in the same second, next to the app's `SCREEN_TIME_TIMING op=register` line.
5. End the session. Close the app, launch it without the argument, start a session, request a break, and end the session. Collect the log again.

Acceptance:

- Step 3 records the lock-hold time of at least one Monitor callback section, which is the done-when of #113. The value replaces "unverified" for that section only; other sections stay unverified until a run records them.
- Step 4 shows whether the access read, a lock wait or neither accounts for the 0.3 s and 0.5 s of #119. If the lines do not account for them, record that, and #119 stays open.
- Step 5 shows no `MONITOR_TIMING` line after the launch without the argument, which shows that the launch removed the flag.
- The regression checks of the stop marker design still pass in this run: the break re-blocks about 3 minutes after it starts, and a session end lifts the focus restrictions.
- If no line arrives by `log collect` or by Console although the flag is on, record the commands and their output. Then #113 stays open, and a new spec decides another route or records why the time cannot be measured.

## Verification for the implementation

Follow `AGENTS.md` and [README verification](../../README.md#실행과-검증).

- `Integration/` and `App/` changes, SDK tests with fakes:
  - The flag: a missing, undecodable or other-version file and the ages -1 s, 24 hours + 1 s are off; the ages 0 and 24 hours are on.
  - The app writes the flag with the argument and removes it without, through a seam for the directory; a failed write or removal does not throw.
  - The line sequence of a callback that runs at attempt 0, of one that finds the lock busy and skips, and of one whose retries run out.
  - The `activity` value for a focus, break, everyday and probe name; no line contains the UUID of the name.
  - With and without the wrappers, a fake store and fake clients count the same lock attempts and the same calls, and the session ends in the same state.
  - Without a valid flag the callback path builds no wrapper and emits no line.
- Compile the App and the Monitor.
- Build an unsigned device Release build, and search every file of its `FocusMonitor.appex` for `MONITOR_TIMING` and `monitor-timing.json`; both must be absent. First run the same search on a Debug build and confirm that it finds both, so that the search is known to see them.
- The [physical-device verification](#physical-device-verification) above. Without it, the lock-hold time of Monitor sections stays unverified.

## Left to the builder

- The names and the files of the flag type, the wrappers and the recorder, and whether the Monitor reuses `DiagnosticMonitoring` and `ScreenTimeOperation`.
- How the recorder joins the wrappers of one callback, and how `cb` stays correct if two callbacks run at the same time in one process.
- The exact search command for the Release check.
