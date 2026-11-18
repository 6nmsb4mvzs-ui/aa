# Installing Sidestreet on your iPhone (free Apple Account)

You need:

- A Mac with **Xcode 16 or newer** (Xcode 26 recommended), installed from the Mac App Store.
- Your iPhone (iOS 17 or newer) and a USB cable (or the same Wi-Fi network after the first install).
- A free **Apple Account** (the one you use for the App Store / iCloud).

No paid Apple Developer Program membership is required. The app is never published on the App Store.

---

## 1. Get the project onto your Mac

Either clone it:

```bash
git clone https://github.com/6nmsb4mvzs-ui/aa.git Sidestreet
cd Sidestreet
git checkout claude/ios-urban-discovery-app-r1mnwg
```

…or on GitHub choose **Code → Download ZIP**, unzip it, and open the folder.

## 2. Open the project in Xcode

Double-click **`Sidestreet.xcodeproj`** (the file with the blue Xcode icon).

> Don't open `Package.swift` — that file exists only so the discovery engine's tests can run on any computer.

If Xcode asks to "Update to recommended settings", you can click **Perform Changes** or ignore it — either is fine.

## 3. Add your free Apple Account to Xcode

1. In the menu bar choose **Xcode → Settings…** (⌘,).
2. Open the **Accounts** tab.
3. Click **+** (bottom left) → **Apple Account** → sign in.
4. Your account now appears with a team named **"Your Name (Personal Team)"**. Close the window.

## 4. Select your Personal Team and set a unique bundle identifier

1. In Xcode's left sidebar, click the top item **Sidestreet** (blue icon).
2. In the middle pane, under **TARGETS**, select **Sidestreet**.
3. Open the **Signing & Capabilities** tab.
4. Make sure **Automatically manage signing** is ticked.
5. **Team:** choose **Your Name (Personal Team)**.
6. **Bundle Identifier:** change `com.yourname.sidestreet` to something unique, e.g.
   `com.janedoe.sidestreet` (letters, numbers, dots and hyphens only).

   Apple requires every bundle identifier to be unique worldwide. If you see
   *"Failed to register bundle identifier"*, just change it again (add a few letters).
7. Do the same for the **SidestreetTests** target if you want to run tests on the phone
   (Team = Personal Team; bundle ID e.g. `com.janedoe.sidestreet.tests`). Not needed just to install the app.

The status line under "Signing Certificate" should show **Apple Development** with no red errors.

## 5. Prepare your iPhone

1. Connect the iPhone with a cable and unlock it. Tap **Trust This Computer** if asked.
2. Turn on **Developer Mode** (required since iOS 16):
   **Settings → Privacy & Security → Developer Mode → On**, then restart the phone and confirm.
   (The option appears after the phone has been connected to Xcode once.)

## 6. Choose the iPhone as the build destination

At the top of the Xcode window, click the device menu next to the ▶︎ Run button and pick **your iPhone** (under "iOS Device").

## 7. Build and install

Press **▶︎ Run** (⌘R). Xcode compiles the app and installs it on the phone.

The first time, iOS blocks apps from a new developer:

1. On the iPhone open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your Apple Account → **Trust "Apple Development: …"** → **Trust**.
3. Press ▶︎ Run in Xcode again (or tap the Sidestreet icon).

When the app opens, choose **Use my location** (iOS asks for "While Using the App" permission) or **Search a city**.

## 8. Free provisioning limits — the 7-day expiry

With a free Apple Account:

- The app's signature **expires after 7 days**. After that it won't open (it shows "unavailable" or closes immediately). Your data on the phone is kept.
- You can have **up to 3 apps** installed from free provisioning at once.
- Xcode can create a limited number of new App IDs per week (about 10).

## 9. Re-installing / refreshing the app

To renew the 7-day period at any time:

1. Connect the iPhone (or be on the same Wi-Fi after enabling **Window → Devices and Simulators → Connect via network** once).
2. Open the project in Xcode, select your iPhone, press **▶︎ Run**.

That's it — the app is re-signed for another 7 days. Search history and settings are preserved because the bundle identifier stays the same.

If something goes wrong:

| Problem | Fix |
|---|---|
| "Untrusted Developer" | Step 7 (trust the developer profile). |
| "Failed to register bundle identifier" | Change the bundle ID to something more unique (Step 4). |
| "Developer Mode disabled" | Step 5. |
| "Could not launch… device locked" | Unlock the phone and press Run again. |
| "Maximum number of apps for free development profiles reached" | Delete another free-provisioned app from the phone. |
| Build errors after updating Xcode | **Product → Clean Build Folder** (⇧⌘K), then Run. |

## Optional extras

- **Run the tests in Xcode:** choose an iPhone **Simulator** as destination and press ⌘U.
- **Run the engine tests without Xcode:** `swift test` in the project folder (Mac or Linux with Swift 6).
- **YouTube videos on profiles:** see *Settings → YouTube videos* in the app for a free API key walkthrough.
- **Try the interface without network:** *Settings → Demo mode* shows clearly-labelled fictional sample places.
