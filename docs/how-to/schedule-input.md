# Schedule text to send to a pane

The clock menu in the status bar can queue text to type into a pane at a
future date and time. It is useful for a command you want to fire off after
a meeting, or a follow-up prompt for an agent you won't be watching.

## Create a schedule

Open the clock menu in the status bar and fill in a date and time, the text
to send, and whether to append a trailing newline (so it behaves like the
text plus Return rather than just typing it in). The schedule applies to
whichever pane was active when you created it.

## Manage existing schedules

Existing entries show up in the same clock menu, where you can edit or
delete them. A few things worth knowing:

- Past or already-sent entries are removed automatically, so the menu only
  ever shows what's still pending.
- Closing the pane a schedule targets removes that schedule too. It doesn't
  fire against a pane that no longer exists.
- Nothing is sent if Mytty isn't running at the scheduled time. It doesn't
  queue up and fire late on the next launch.
