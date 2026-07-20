# Connect to your Mac from an iPhone

This covers pairing the Mytty iOS remote app with your Mac, what you can do
once connected, and how Attention push notifications reach the phone.

## Pair the phone

On the Mac, open **Settings > iOS Remote Access** and press
**Generate Pairing Code**. Enter the six digits it shows into the Mytty iOS
app. The Mac is discovered over Bonjour, and the connection that results is
paired and encrypted.

The Mac listens on port 51820, falling back to an automatic port if that one
is taken; Settings shows whichever port is actually in use. If Bonjour can't
reach the Mac, for example over a VPN like Tailscale, enter the address
directly instead of scanning for it. A pairing attempt can be cancelled, and
gives up on its own after 30 seconds.

Once paired, a Mac can be renamed and re-addressed later from the iOS app's
settings screen. Its label and connection method, either a Bonjour service
name or a manual host and port, are editable without re-pairing.

## Work in a pane from the phone

<p>
  <img src="../images/ios-pane.png" alt="A Mac pane mirrored on the phone, with the control key bar" width="280">
</p>

From the phone you browse windows, tabs, and panes, then open one to watch it
live. The pane renders in the Mac's own terminal colors, including bold, dim,
and reverse video, with a block cursor, and up to 10,000 lines of scrollback
mirror to the phone. The view only follows new output while you're scrolled
to the bottom, so scrolling up to read something holds your position instead
of jumping away. Full-screen terminal apps such as agents, pagers, and
editors have no scrollback of their own to mirror; scrolling one of those
panes instead forwards mouse-wheel input to the Mac, so the app's own
scrolling (an agent's history view, for instance) responds from the phone.

Typing sends input straight to the pane. Japanese composes through the
iPhone's own IME: kanji conversion happens on the phone, and only the
committed text is sent. A control-key bar covers Ctrl, Option, arrows, and
the other keys a physical keyboard would supply. The bar's paste key sends
the iPhone's clipboard to the pane as a paste; the copy button in the pane's
toolbar opens a frozen snapshot of the buffer where you can select text with
the standard iOS selection UI, or copy everything at once with **Copy All**.

If the connection drops, the pane shows a banner, dims its now-stale content,
and disables input until you tap **Reconnect**, or until the app returns to
the foreground, which reconnects on its own. Either way you land back on the
same pane; if that pane closed on the Mac in the meantime, the app falls back
to the pane list, and to the tab list if the whole tab is gone.

Opening a browser pane shows its title and current URL, kept in sync as the
Mac navigates, with buttons to open the same page in an in-app Safari view or
copy the URL.

## Get Attention alerts as push notifications

<p>
  <img src="../images/ios-push.png" alt="An Attention push notification naming the Mac it came from" width="280">
</p>

Once paired, Attention items also reach the phone through Apple Push
Notification service, so an agent that needs approval while you're away from
the desk still alerts you with the remote app closed. The push fires
whenever Mytty isn't the frontmost app, which includes the case where the
pane that raised it is still focused on screen. That is what walking away
from a running agent actually looks like, so you never get the same alert
twice, once from the Mac's own banner and once from the phone.

The relay carrying these pushes is a Cloudflare Worker
(`cloudflare/push-relay`), so there's nothing to configure on the Mac itself.
The phone registers with the relay directly and hands the Mac back only an
opaque handle. Alert text never reaches the relay in the clear: the Mac seals
it with the key it and the phone established while pairing, and a
notification service extension on the phone unseals it right before iOS
shows it. What Cloudflare actually sees is a device token, a random Mac
identifier, and ciphertext; a phone that can't decrypt a given push falls
back to a placeholder that names only the kind of Attention item, not its
content.

Tapping the alert opens the app on the exact pane that raised it, descending
through the right Mac, window, and tab on the way. If that pane has since
closed, you land on the Mac's session instead.

You can turn the toggle off to stop pushes without unpairing. If you're
running the iOS app under your own Apple Developer team, self-hosting the
relay is required rather than optional. See
[`cloudflare/push-relay/README.md`](../../cloudflare/push-relay/README.md)
for how to do that.
