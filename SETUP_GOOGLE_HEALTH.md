# Connect your Pixel Watch (Google Health API)

Google is turning off the legacy Fitbit Web API on **October 30, 2026**.
Dialed now reads your Pixel Watch data through its replacement, the
**Google Health API** (`health.googleapis.com/v4`). You only need to do this
once. It takes about 5 minutes.

## 1. Make sure your watch data is in your Google account
Open the **Google Health** app (formerly the Fitbit app) on the phone your
Pixel Watch pairs with. Sign in with your Google account and confirm that
recent sleep and heart data show up there. Google requires this account
link before any app can read your data.

## 2. Create a Google Cloud project
1. Go to <https://console.cloud.google.com> and create a project (e.g. "Dialed").
2. Open **APIs & Services → Library**, search for **Google Health API**, and click **Enable**.

## 3. Configure the consent screen (Google Auth Platform)
1. **Audience:** set User type to **External**. Under **Test users**, add your own Google email.
2. **Data Access → Add or remove scopes:** search "Google Health" and add:
   - `googlehealth.activity_and_fitness.readonly`
   - `googlehealth.health_metrics_and_measurements.readonly`
   - `googlehealth.sleep.readonly`
   - `googlehealth.nutrition.readonly`
   - `googlehealth.profile.readonly`
3. **Stay connected:** in Testing mode, Google expires your sign-in after
   **7 days**. To avoid reconnecting every week, set **Audience →
   Publishing status → In production**. Apps with fewer than 100 users
   don't need Google's verification; you'll see an "unverified app" screen
   when you connect. Tap **Advanced → Continue**.

## 4. Create an iOS OAuth client
**Clients → Create client → Application type: iOS**
- Bundle ID: `org.robertwiscount.Dialed`

Copy the **Client ID**. It ends in `.apps.googleusercontent.com`.

## 5. Connect in Dialed
In Dialed, go to **Home → Devices** (the antenna button, or the bottom bar
menu **More → Devices & data check**) and open **Google Pixel Watch**.
Paste the Client ID, tap **Save**, then tap **Connect with Google**. The
first sync pulls the last 14 days.

You don't need a URL scheme or an Info.plist change. iOS clients sign in
with PKCE through the reversed client ID scheme, which the system sign-in
sheet handles itself. If you'd rather hard-code the ID, add
`GoogleHealthClientID` to the target's Info.plist.

## WaterH bottle
WaterH reaches Dialed through Apple Health:
1. In the **WaterH** app settings, turn on **Apple Health** and allow it to write **Water**.
2. In **Dialed → Devices → Apple Health**, tap **Review access** and allow **Water**.

**Devices → Data check** shows "WaterH via Apple Health" once sips arrive.
