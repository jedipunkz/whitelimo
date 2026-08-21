# whitelimo

A menu bar app for macOS that controls [Nature Remo](https://nature.global/) appliances.

Give it an access token and it fetches the appliances registered on your account from the Nature
Remo Cloud API, then builds a menu for them. The result is cached, so the menu is ready the moment
the app launches from then on.

## What it does

- Lives in the menu bar. No Dock icon, no windows except the token prompt and the occasional alert.
- Builds the menu from what each appliance can actually do:
  - **Air conditioner**: turn on / off, operation mode, temperature, fan speed
  - **Light / TV**: the buttons the API reports (on, off, power, input, and so on)
  - **Anything else**: the learned infrared signals
- Shows the outcome of the last action at the top of the menu and in the menu bar tooltip.
- Reports failures in an alert and records them in `whitelimo.log`.

Only appliances driven by infrared are controllable. Smart meters, smart locks and other
non-infrared devices cannot be given a menu, so whitelimo lists them under **Devices Without
Controls** rather than hiding them.

## Requirements

- macOS 13 Ventura or later, on Apple silicon or Intel
- A Nature Remo access token, issued at <https://home.nature.global/>

## Install

Download the zip from [Releases](https://github.com/jedipunkz/whitelimo/releases), unzip it and move
`whitelimo.app` into `/Applications`. There is no installer.

| File | For |
| --- | --- |
| `whitelimo_<version>_macos_universal.zip` | Every Mac — the binary is universal |

The app is signed ad hoc rather than with a paid Developer ID, so Gatekeeper does not recognise it.
Open it the first time with **right-click → Open**, or clear the quarantine flag yourself:

```console
xattr -dr com.apple.quarantine /Applications/whitelimo.app
```

Verify the download against the `SHA256SUMS.txt` published with the release:

```console
shasum -a 256 -c SHA256SUMS.txt
```

## Usage

1. Launch `whitelimo.app`. An icon appears in the menu bar.
2. On the first run the token prompt opens by itself. Later you can reach it from the menu with
   **Set Access Token…**.
3. Paste the access token issued at <https://home.nature.global/> and click **OK**. (**Issue a
   Token…** opens that page in your browser.)
4. The token is checked, your appliances are fetched, and the menu is built.
5. From then on, pick an appliance from the menu bar and choose what it should do.

Choose **Refresh Appliances** after adding, removing or renaming a device — and also after changing
the operation mode of an air conditioner, because the temperature and fan speed a unit accepts
depend on the mode it is in.

## Configuration file

The state lives in `~/Library/Application Support/whitelimo/config.json`. Set the `WHITELIMO_CONFIG`
environment variable to keep it somewhere else.

- **The access token is stored there in plain text.** The file is created readable and writable by
  you alone, but treat it with care on a shared Mac. To retire a token, revoke it at
  <https://home.nature.global/>.
- The appliance list in the file is only a cache. Delete it and **Refresh Appliances** rebuilds it.
- Activity is logged next to it in `whitelimo.log`, which starts over once it passes 1 MB.

## Development

```console
swift test                      # the API client, the menu tree and the config store
make app                        # dist/whitelimo.app, current architecture only
make run                        # build it and launch it
VERSION=v1.2.3 make package     # dist/whitelimo_v1.2.3_macos_universal.zip, universal
```

The code is split so that everything except the menu itself can be tested without AppKit:

| Target | What it holds |
| --- | --- |
| `Sources/RemoKit` | The Nature Remo Cloud API client and its models |
| `Sources/MenuKit` | Turning appliances into a menu tree, and running what was clicked |
| `Sources/WhiteLimoCore` | The configuration file and the log |
| `Sources/whitelimo` | The status item, the menu and the alerts |

`Scripts/bundle.sh` assembles `whitelimo.app` around the binary `swift build` produces: it fills in
`Resources/Info.plist`, draws the app icon with `Scripts/make-icon.swift`, and signs the bundle ad
hoc. A release build is universal; `make app` builds for the current architecture only because it is
much quicker.

## Releasing

Run the `Release` workflow from the Actions tab and pick `patch`, `minor` or `major`. It works out
the next version from the most recent tag, builds and tests the commit, tags it, and publishes the
zip along with `SHA256SUMS.txt`. Tick **dry run** to build and package without tagging or publishing
anything.

Pushing a `vX.Y.Z` tag by hand produces the same release, which is the way to use a version that is
not simply the next one.

## License

MIT License. See [LICENSE](LICENSE).
