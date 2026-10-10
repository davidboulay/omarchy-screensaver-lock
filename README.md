# Screensaver Lock

An Omarchy plugin that locks your session **every time** the screensaver is dismissed. Your desktop never shows in between: dismissing the screensaver goes straight to black, then to the lock screen.

![Screensaver Lock](preview.png)

## Why

Stock Omarchy starts the screensaver after `idle.screensaver` seconds (150 by default) and locks after `idle.lock` seconds (300), but only if the screensaver is still up at that point. If you come back and press a key while the screensaver is running, Omarchy treats that as activity, cancels the pending lock and shows your desktop. Whether you get a lock screen therefore depends on how long you were away.

Setting `idle.lock` equal to `idle.screensaver` is not a fix: locking closes the screensaver, so you would never see it.

## What it does

- Watches Hyprland for screensaver windows (`org.omarchy.screensaver`). Nothing is polled while you work.
- When a screensaver window closes and the session is not already locked, it runs `omarchy-system-lock`.
- Hides the gap between "screensaver closed" and "lock screen up" with a black curtain on every screen:
  - While the screensaver runs, the curtain is already there but transparent. It is a click-through layer surface that never takes keyboard focus.
  - The moment the screensaver closes, the curtain turns black in the same frame and the lock starts behind it.
  - Two seconds after the lock is confirmed (the lock screen now covers everything), the curtain is removed.
  - If the lock does not arrive within 8 seconds, for example because PAM is not configured, the curtain is removed anyway, so you can never be stuck behind a black screen.
- When the regular `idle.lock` timeout is what closes the screensaver, the session is already locked and the plugin does nothing extra.

It works with Omarchy's built-in lock screen and with any lock-screen plugin that implements the stock `lock` IPC (`omarchy-shell lock isLocked`). It also applies to a screensaver started by hand (`omarchy-launch-screensaver force`): dismissing it locks.

## Install

Review the repository, then add the plugin:

```bash
omarchy plugin add https://github.com/davidboulay/omarchy-screensaver-lock.git
```

Accept the prompt to enable it. For an unattended install from a repository you already trust:

```bash
omarchy plugin add https://github.com/davidboulay/omarchy-screensaver-lock.git --enable --yes
```

The plugin is `keepLoaded`, so run `omarchy restart shell` after enabling or updating it if it does not take effect.

### Try it

```bash
omarchy-launch-screensaver force
```

Wait a few seconds, then press a key. You should see black, then the lock screen, never your desktop.

## Update

```bash
omarchy plugin update io.github.davidboulay.screensaver-lock
```

## Disable or remove

```bash
omarchy plugin disable io.github.davidboulay.screensaver-lock
omarchy plugin remove io.github.davidboulay.screensaver-lock
```

Disabling restores the stock behavior immediately. The plugin writes no files and edits no configuration, so removing it leaves nothing behind.

## Requirements

Everything ships with a stock Omarchy 4 install: the screensaver (`ttfx` in a supported terminal), `omarchy-system-lock`, `omarchy-shell` and Hyprland. There are no other dependencies.

## Troubleshooting

```bash
omarchy-shell screensaverLock status            # curtain state, open screensaver windows
omarchy-shell screensaverLock setDryRun true    # show the curtain on dismiss, but don't lock
omarchy-shell screensaverLock curtainDown       # remove the curtain by hand
journalctl --user | grep 'screensaver-lock:'    # what happened and when
```

If you test with `pkill -f` or `pgrep -f`, keep the literal window class out of your own command line, or the pattern will match your own shell.

## Security

The plugin runs two stock Omarchy commands, `omarchy-shell lock isLocked` and `omarchy-system-lock`. It reads no files, makes no network requests and stores nothing.

## License

MIT. See [LICENSE](LICENSE).
