# Open a pane on another Mac

A Mytty pane can mirror a terminal running on a different Mac. The pane shows that terminal's screen and sends your typing back to it, so an agent you started on a desktop stays reachable from a laptop without a second SSH session.

This is the same connection the iOS remote app uses, with a Mac on the client side instead of a phone.

## Turn on remote access on the Mac you want to reach

On the Mac whose terminals you want to see:

1. Open **Settings > Remote Access** and turn it on.
2. Click **Generate Pairing QR Code**.
3. Click **Copy Pairing Link**.

The link is a `mytty://pair?...` URL carrying a one-time token. It expires in two minutes, the same as the QR code beside it, so paste it on the other Mac before it runs out.

## Pair from the Mac you are sitting at

1. Open **Settings > Remote Access** and click **Add Mac…** in the Remote Macs section.
2. Paste the pairing link.
3. Give the Mac a name — it is what the pane badge and the status bar will show.
4. Pick the Mac from the address list if it appears there, or enter its address and port by hand. Macs advertising Mytty on the local network show up automatically.
5. Click **Pair**.

Pairing stores a key under `~/Library/Application Support/mytty/remote-hosts.json`, readable only by you. It is separate from the record of devices allowed to connect *in*: either direction can be set up without the other.

## Open the pane

Choose **Pane > Open Remote Pane…**. Pick a paired Mac, then a pane from the list, and it opens beside the focused pane.

The pane list only fills in once the connection is up, so it may be briefly empty. Panes already mirroring a third Mac are not offered: Mytty does not chain remote panes.

## What a remote pane can and cannot do

A remote pane is deliberately not a local terminal, and it never pretends to be one:

- It wears a badge naming the Mac it mirrors, and the status bar names that Mac instead of a working directory.
- It shows the agent the host reports — the provider, its model, remaining context, and a marker when that agent is waiting on you. Those numbers come from the host; nothing about the agent is measured locally.
- Quota and cost meters stay local-only. They describe *this* Mac's account, so they would be misleading next to another Mac's agent.
- `mytty-ctl` does not list remote panes. Its pane IDs have to be ones this Mac can split, close, or type into.
- Session restoration reopens the pane and reconnects. It does not restore a process, because there is no local process to restore.

Panes onto the same Mac share one connection, and closing the last of them closes it.

## Known limits

What you see is the host's screen re-encoded as styled text, not a video of its terminal. Colours, bold, faint, inverse, italic, underline (including curly and coloured underlines) and strikethrough all survive. Inline images, Sixel graphics and font ligatures do not.

Typing, discrete keys (including Control and Option combinations), pasting, scrolling and selecting text all work. Text selection copies from the mirrored buffer.

If the host closes the pane, the mirror stays on screen so you can still read and copy it, but input stops for good.
