# Privacy Policy — Shadchan (שדכן)

**Last updated: August 21, 2026**
**Effective date: August 21, 2026**

Shadchan ("the Application") is a mobile application that helps matchmakers manage
contacts, match ideas, notes and reminders related to the matchmaking process. The
Application is developed and operated by **Gilad Shtruzman** ("the Service Provider",
"we", "us"), who acts as the data controller for the limited processing described
below. You can reach us at any time at **giladsh22@gmail.com**.

This policy explains what information the Application processes, how it is used, where
it is stored, who else can see it, and what control you have over it.

---

## 1. Summary

We think the honest short version matters more than the legal long version, so here it is:

- **The Application is local-first.** Your database lives on your device. The
  Application works completely offline and with no account at all.
- **We do not use advertising, analytics or tracking SDKs.** The Application contains no
  ad network, no analytics SDK, no crash-reporting SDK, no cookies, no pixels and no
  cross-app or cross-site tracking. We do not collect your IP address, your browsing
  behaviour, an advertising identifier, or a record of which screens you visit.
- **We never sell personal information**, and we never share it with advertisers or data
  brokers.
- **Nothing leaves your device automatically.** Data leaves the device only when you sign
  in and enable cloud backup, when you use an AI-assisted import, when you send a support
  request, when the community area is enabled for your account, or when you yourself
  choose to share, export or publish something.

The rest of this policy is the long version.

---

## 2. Information you enter into the Application

You may enter information manually, including:

- First name and last name
- Gender
- Age
- Religious level or style
- City
- Phone number
- How you know the person
- Private notes
- Photographs
- Favourite markers
- Information about match ideas and notes attached to them

This information is stored in the Application's local database on your device. See
section 5 for where it goes if you enable cloud backup.

---

## 3. Information the Application reads from your device

### Contacts

If you choose to use contact import, the Application requests permission to read the
contacts on your device in order to show you names and phone numbers as import
candidates. To make repeat visits to the import screen faster, the list of import
candidates may be cached locally on the device. **Contacts you do not choose to import
are not added to the Application's records**, and no contact data is transmitted anywhere
as part of this feature.

### Call log (Android only)

In the card-swipe import view, the Application may request access to the call log in
order to sort the suggested contacts by most recent calls. **The call log is used for
local sorting only.** It is never uploaded, never transmitted off the device, and is
never stored as a person record unless you choose to import that contact.

### Photos and media

If you choose to add a photograph, the Application accesses your gallery or the device
media picker so you can select an image and save it to a person record.

### On-device face detection

To centre a photograph on the face rather than cropping it off, the Application runs
Google ML Kit face detection. **This runs entirely on the device.** No photograph, and no
face data derived from it, is transmitted anywhere for this purpose.

### Content shared into the Application

If you share text or an image into the Application from another app — WhatsApp, for
example — the shared content is copied temporarily to your device and shown to you so you
can decide whether to add it to an existing person or create a new one. The content is
saved to a person record only after you take a deliberate action.

### Backups you create yourself

If you choose to export or import a backup, the Application creates or reads a JSON file
that may contain everything stored in the Application, including people, ideas, notes and
local photographs. A file you export is yours; once it leaves the Application, it is
subject to wherever you put it.

The Application does not store dates of birth. Older versions did, so a backup file created by one of them may contain a date of birth — in that case the Application reads it during the import, converts it to an age, and does not keep the date itself.

### Notifications

If you allow notifications, the Application shows local reminders you set yourself on ideas and on people, and an invitation to come back if you have not opened it for a week. They are scheduled on the device;
no reminder content is sent to a server.

### Application version check

The Application checks the public app-store listing for a newer version so it can tell
you when an update is available. This request carries no personal information.

---

## 4. How the information is used

Information is used to operate the features of the Application, and for nothing else:

- Managing person records
- Creating and tracking match ideas
- Adding private notes and notes on ideas
- Searching, filtering and sorting
- Importing contacts you select
- Sorting import candidates by recent calls on Android
- Displaying and storing photographs
- Sharing that you initiate
- Receiving text or images you shared into the Application
- Backup and restore
- Local reminders you set yourself
- The community area and leaderboard, if you are signed in (section 7)
- Handling support requests you send (section 9)

We do not use your information for advertising, profiling, automated decision-making with
legal effect, or marketing. **We will not send you marketing communications.**

---

## 5. Where information is stored

As of August 21, 2026, information is stored **locally on the device** on which the
Application is installed: in the Application's local database, and in local files for
photographs and temporary backups. The Application works fully offline and with no
account.

The Application does not require an account. It offers to sign in once, and you may
decline and keep working locally forever.

**If, and only if, you choose to sign in with a Google or Apple account**, cloud backup is
enabled: a copy of your database — people, ideas, notes and photographs — is stored in
Google's Firebase services (Cloud Firestore and Cloud Storage) under your account alone.
The backup runs automatically when the Application opens and closes, and its only purpose
is to let you restore your database on a new device.

Access to the backup is restricted by server-side security rules to the account that
created it, and the Application provides no way whatsoever to view another user's
database. This data is not used for advertising, analytics, or sale to third parties.
Signing out stops the backup; the database on the device stays exactly as it is.

Firebase App Check is used to verify that requests come from a genuine installation of the
Application. It does not identify you.

---

## 6. AI-assisted import (Google Gemini)

The Application offers AI-assisted import: you can hand it a spreadsheet, or a WhatsApp
chat export, and it will read the people out of it for you instead of you typing them in
one at a time.

When you use this feature, **the text of the file you selected is sent to Google's Gemini
model** through Firebase AI on the Vertex AI platform, so that it can be parsed into
person records. This text may contain personal information about the people in that file —
names, ages, phone numbers, and whatever else the file happens to contain.

What you should know about this:

- **It only happens when you start an import.** No content is sent to the model in the
  background, and the feature is never automatic.
- **Only text is sent.** Photographs are never sent to the model.
- **Processing is governed by the Google Cloud data-processing terms**, which are a
  contractual commitment that the content is not used to train Google's models and is not
  retained.
- **Requests are processed on Google's global endpoint**, which means processing may occur
  outside your country of residence, including outside the European Economic Area. See
  section 13.
- The parsed results are shown to you for review, and are written to your database only
  after you accept them.

If you would rather not send anything to a third party, do not use the AI import — every
person record can be created manually, and the rest of the Application is unaffected.

---

## 7. Community area and leaderboard

The Application includes a community area showing aggregate figures across all
matchmakers — activity points, number of active matchmakers, friends added, ideas opened,
couples who started dating, and engagements — along with a leaderboard of the ten most
active matchmakers.

**The community area is open only to users who signed in with a Google or Apple account.**
If you use the Application without signing in, you send no data to this server at all, you
are not counted in the community figures, you do not appear in the leaderboard, and you do
not see them.

For this purpose, and only for this purpose, two kinds of data about a signed-in user are
stored on the server:

- **Activity counters** — how many activity points you accumulated today, this week, this
  month and all-time, and how many friends, ideas, couples dating and engagements lie
  behind them. These are numbers only.
- **The name and picture in your profile** — so that you can be shown in the leaderboard.

**No detail about any person in your database is ever sent to this server.** Not a name,
not an age, not a phone number, not a note, not a photograph of them. What other
matchmakers see is the name and picture from your own profile, and the numbers.

By default, the name and picture from your profile do appear in the community leaderboard.
You can turn this off at any time via **"Appear in the community under my name"** in the
"Privacy and my database" screen — your activity is then still counted in the community
totals, but with no name, no picture and no place in the leaderboard. In the same screen
you can switch on **"Keep me private"**, which stops anything at all being sent to the
community, and you can delete your community data from the server entirely.

Please note: the community data is read by the Application on every device it is installed
on, in order to compute the totals and the leaderboard. **Treat a name shown in the
leaderboard as visible to every user of the Application.**

---

## 8. "Mazal tov! A new couple is engaged" announcements

When a matchmaker marks in the Application that a couple has reached the wedding, a short
record is sent to the server so that the announcement can be shown to other users.

**No detail about either member of the couple is ever sent to this server — not a name,
not a first name, not a photograph, not an age, nothing.** The record holds a timestamp,
the matchmaker's account identifier, and their own proposal id (a random identifier
generated on their phone, meaningless outside their own database, carried only so a
congratulation can be delivered back). What other users see is that some couple got
engaged.

The Application used to offer to publish the couple's first names and a photograph, once
the matchmaker confirmed they had the couple's consent. **That feature has been removed.**
Two people who are not users of the Application, who agreed to nothing and would have no
way of knowing, are not made public on the strength of a third person ticking a box. The
server itself now rejects any attempt to write a couple's name or picture — it is not
merely that the app declines to.

The only thing that can be added to an announcement is **the matchmaker's own name**.
Right after the wedding is marked, a separate question is asked: may the announcement say
that this match was yours. If you agree, the name from your profile is added — and nothing
else. If you decline, or dismiss the question, the announcement stays nameless. Appearing
in the community leaderboard is not an answer to this question, and it is asked afresh for
every wedding. Immediately afterwards an "Undo" button removes the name and leaves the
announcement nameless.

Note that even a nameless announcement carries the matchmaker's account identifier, and
that identifier is also used by your community record. A matchmaker who appears in the
leaderboard under their name can be identified this way even when the announcement itself
carries no name.

The announcement is temporary: it is shown for up to one week from publication, and the
Application has no screen, list or archive of engaged couples.

---

## 9. Support requests

If you send a problem report or an improvement idea from within the Application, we
receive the text you wrote, an image if you attached one, the name in your profile, and
three technical details about the device: model, operating system, and application
version. These details are shown to you on screen before sending. Support requests are
accessible to the Application's administrators only, and are used solely to handle the
request.

---

## 10. Information about other people

The Application is built around a matchmaker recording information about **other people**,
who are not users of the Application and have not agreed to this policy.

Where data protection law applies to you, you are responsible for that information: for
having a lawful basis to hold it, for handling it fairly, and for responding to the people
concerned if they ask what you hold about them. The Application is designed to help:
records stay on your device by default, they are never shared with other users, and no
detail from your database is ever transmitted to the community server. The only paths by
which such information leaves your device are the ones you initiate — cloud backup, AI
import, an engagement announcement you publish, an export, or a share.

Please use the Application the way you would want someone to use it about you.

---

## 11. Permissions

The Application may request the following permissions, only when they are needed for an
action you chose:

| Permission | Why | Where the data goes |
|---|---|---|
| Contacts | Show device contacts so you can import the ones you pick | Stays on the device |
| Call log (Android) | Sort import candidates by recent calls in the card-swipe view | Stays on the device; sorting only |
| Photos / gallery | Choose a photograph for a person record | Stays on the device unless you enable backup or publish it |
| Notifications | Local reminders you set yourself | Never leaves the device |

You may revoke permissions at any time through device settings, but some features may not
work without the corresponding permission.

---

## 12. Third-party services

The Application uses the following third-party services, which have their own privacy
policies:

- **Google Play Services**, covering Firebase Authentication, Cloud Firestore, Cloud
  Storage, Firebase App Check, Firebase AI (Gemini on Vertex AI), Google Sign-In, and
  Google ML Kit — [Google Privacy Policy](https://www.google.com/policies/privacy/)
- **Sign in with Apple**, if you choose to sign in with an Apple account —
  [Apple Privacy Policy](https://www.apple.com/legal/privacy/)

Beyond these, the Application uses **no advertising networks, no analytics providers, and
no crash-reporting services**.

---

## 13. International data transfers

If you use cloud backup, AI import, the community area or support requests, the data
involved is processed on Google's infrastructure and may be transferred to and processed
in countries outside your country of residence, including outside the European Economic
Area. AI import requests in particular are processed on Google's global endpoint.

Where applicable law requires safeguards for such transfers, we rely on the mechanisms
Google Cloud and Firebase provide for their customers, which include:

- Standard Contractual Clauses (SCCs) approved by the European Commission
- Adequacy decisions or other legally recognised transfer mechanisms
- Your consent, where required and legally permitted

Data protection laws in other countries may differ from those in your jurisdiction.

---

## 14. Sharing and disclosure

The Application does not sell personal information and does not share it with advertisers
or commercial parties.

Beyond the community area, the AI import and the support requests described above,
information leaves the device only at your initiative: if you use sharing, backup export,
opening a backup file, or dialling, the relevant information may be handed to the
application, service or operating system you chose to use. In those cases, the handling of
that information is also subject to the policy of the external service or application you
selected.

We may disclose information:

- as required by law, such as to comply with a subpoena or similar legal process;
- when we believe in good faith that disclosure is necessary to protect our rights,
  protect your safety or the safety of others, investigate fraud, or respond to a
  government request;
- to our trusted service providers who work on our behalf, have no independent use of the
  information disclosed to them, and are bound to the rules set out in this policy.

---

## 15. Legal bases for processing (EEA/UK)

Where the GDPR or UK GDPR applies:

- **Performance of a contract** — operating the features you asked for, including storing
  your records and, if enabled, restoring them from backup.
- **Consent** — device permissions (contacts, call log, photos, notifications), signing in
  and enabling cloud backup, publishing an engagement announcement with details, and using
  AI-assisted import. You may withdraw consent at any time; withdrawal does not affect
  processing carried out beforehand.
- **Legitimate interests** — running the community area for signed-in users, including
  showing your profile name and picture in the leaderboard, which you can switch off at
  any time (section 7); verifying that requests come from a genuine installation
  (App Check); handling support requests you send; and preventing abuse.

---

## 16. Data retention and deletion

- **On-device data** is kept on the device until you update it, delete it, or uninstall
  the Application. We set no retention period on it, because we do not hold it.
- **Cloud backup**, if enabled, is kept under your account until you delete it. It is
  deleted from the server with one tap from "Privacy and my database" — every record, the
  profile and every photo — and the database on your device is left untouched. Signing out
  stops the backup being updated but does not remove it. **Uninstalling the Application
  alone does not delete it.**
- **Community data** — counters, and your name if you approved it — is deleted from the
  server with one tap from "Privacy and my database". **Uninstalling the Application alone
  does not delete it.**
- **Engagement announcements** are shown for up to one week and can be removed immediately
  with the "Unpublish" button.
- **Support requests** are kept only as long as needed to handle the request.
- **AI import content** is not retained by Google under the Google Cloud data-processing
  terms, and is not retained by us.

You can delete people, photographs, notes and ideas from within the Application. If you
exported a backup file or shared information with another application, those copies may
remain outside the Application until you delete them manually.

To request deletion of anything we hold, write to **giladsh22@gmail.com**.

---

## 17. Your rights

Subject to applicable law, you have the right to access, correct, delete, restrict or
object to the processing of your personal data, the right to data portability, and the
right to withdraw consent where processing is based on consent. Most of these you can
exercise directly in the Application — the data is on your device, and the community and
backup data can be deleted from within it.

For anything you cannot do yourself, contact **giladsh22@gmail.com**. You also have the
right to lodge a complaint with your local data protection authority.

### California privacy rights (CCPA/CPRA)

If you are a California resident, you have the right to know what personal information is
collected, the right to delete personal information, the right to correct inaccurate
personal information, the right to opt out of the sale or sharing of personal information,
and the right to non-discrimination for exercising these rights.

**We do not sell or share personal information as those terms are defined under the
CCPA/CPRA**, and we do not use it for cross-context behavioural advertising. To exercise
your rights, contact **giladsh22@gmail.com**.

---

## 18. Opt-out

You can stop any further processing by uninstalling the Application. Note that
uninstalling does not by itself delete community data already stored on the server or a
cloud backup already created. Both have their own delete button on "Privacy and my
database" — use them before you uninstall. If you have already uninstalled, write to us
and we will do it.

---

## 19. Children

The Application is not intended for children under 16 years of age, or such higher age as
required by applicable law, and is not marketed to them. We do not knowingly collect
personal information from children.

If you are a parent or guardian and believe a child has provided us with personal
information, contact us at **giladsh22@gmail.com** and we will delete it.

---

## 20. Security

The Application relies on the storage and permission mechanisms of the operating system
and of Flutter. Cloud backup, community data and support requests are protected by
server-side security rules that restrict each record to the account that created it, and
by Firebase App Check. Although reasonable measures are taken, we cannot guarantee
absolute protection against unauthorised access to the device itself, and no method of
transmission or storage is completely secure.

---

## 21. Data breach notification

If a data breach occurs that affects your personal data, we will notify you in accordance
with applicable legal requirements, including, where required, the nature of the breach
and the steps being taken to address it.

---

## 22. Changes to this policy

This privacy policy may be updated from time to time. In the event of a material change,
the updated version will replace the previous one and carry a new update date. Where
required by law, we will seek your consent to material changes before they take effect.
Previous versions are available on request at **giladsh22@gmail.com**.

---

## 23. Contact

For questions about privacy, or requests concerning your information:

**Gilad Shtruzman** — **giladsh22@gmail.com**

---

*A Hebrew version of this policy is available in [PRIVACY_POLICY.md](PRIVACY_POLICY.md).
In case of any discrepancy between the versions, the Hebrew version prevails.*
