# Privacy Policy — Shadchan

Last updated: August 30, 2026

This policy applies to the **Shadchan** application and its information website. The Application is developed and operated by Gilad Shtruzman ("we"), the controller of the processing described here. Privacy contact: **giladsh22@gmail.com**.

## In brief

The Application is local-first: the active database lives on the device and continues to work offline. An account is nevertheless required, and a cloud backup is kept automatically in Firebase under that account's identifier. The Application contains no advertising, analytics SDK, crash-reporting SDK, cookies or behavioural tracking, and we do not sell personal information.

## 1. Information processed

### Your account

You can sign in with Google, with Apple on supported Apple devices, or with an email address and password. Firebase Authentication processes the account identifier, sign-in provider, email address and basic profile details supplied by the provider. Passwords for email accounts are handled by Firebase and are not visible to us. For security and abuse prevention, Firebase may also process IP addresses, user-agent strings and sign-in logs. Before sign-in or after sign-out, the Application may create a temporary technical anonymous Firebase identifier; it receives no backup and cannot pass the sign-in gate.

### Matchmaking database

You may enter information about yourself and other people, including names, gender, age, religious style, city, telephone number, contact people, how you know them, photographs, private notes, preferences, reminders, match ideas and their handling history. People in your database do not become users and are not automatically notified.

### Contacts and photographs

- Contact import displays names and phone numbers on the device and adds only the contacts you select. The candidate list may be cached locally for speed.
- On Android the contact's "favourite" flag is also read, so favourites appear at the top of the import list. It is used only for local sorting and is never uploaded.
- Selecting a photograph opens the system media picker. Google ML Kit face detection is used entirely on-device to help crop the image; neither the image nor face-detection output is sent to ML Kit in the cloud.
- Content shared into the Application from another app is copied temporarily and added to the database only after an explicit choice.

### Reminders and files

Reminders are local notifications scheduled on the device. Exporting JSON or Excel, sharing a card, or opening a backup file happens at your direction. A copy delivered to another app or stored outside Shadchan is under your control.

## 2. Purposes

Information is used to operate the Application: database management, match ideas, search and filtering, reminders, imports and sharing you request, backup and restore, community features, support, security and abuse prevention. We do not use it for advertising, marketing, commercial profiling or automated decisions with legal effect, and we do not send marketing communications.

## 3. Local storage and cloud backup

Hive and local files are the active source of truth, so the Application can work offline after sign-in. An account is required to separate different users' databases on one device and to make restoration possible.

A backup under `users/{uid}` in Cloud Firestore and Cloud Storage includes people, ideas, notes, activity and status history, the profile and photographs. It runs on app open, pause/close and after changes, and is used to restore the database on a new device. Server-side rules restrict it to the account that created it; the Application has no administrator screen or cross-account database search.

Signing out first attempts a final backup. Only after it succeeds does the Application disconnect the account and clear the local database, so the next user cannot see it. The cloud copy remains and returns when the same account signs in again.

## 4. Gemini-assisted import

Only when you start an AI-assisted import, text extracted from an Excel file, chat backup or profile card is sent to Gemini through Firebase AI Logic and Vertex AI at a global endpoint. It may contain names, ages, telephone numbers and other content in the selected file. Photographs are not sent to the model in this flow. Parsed results are shown for review and written only after acceptance.

Use is governed by the Google Cloud and Generative AI service terms. Google states that it will not use customer data to train or fine-tune AI/ML models without permission or instruction, but may process or retain data as needed for security, abuse monitoring, operation or caching under its settings and terms. If you do not want to send text to a model, use the manual and non-AI import paths.

## 5. Community and public profile

An account may have a community document with period activity counters: points, friends, ideas, couples dating and engagements. Other signed-in users read those counters to produce community totals and the leaderboard.

If you choose to appear by name, the following details about **you only** may also be visible: profile name, profile picture, short introduction, answers you chose to share, a community benefit and a WhatsApp number you entered voluntarily. Treat them as visible to every signed-in user. You can hide the named profile, stop community publishing or erase the community document from "Privacy and my database".

No name, phone number, note or photograph of a person in your matchmaking database is written to the community member document.

## 6. Engagement announcements and congratulations

When an idea is marked as a wedding, a temporary community announcement contains a timestamp, the matchmaker's account identifier and a random idea identifier meaningless without their local database. It contains no name, photograph, age or other detail about the couple. The matchmaker's own name is added only after separate consent. It is displayed for up to one week and intended for Firestore TTL deletion after a retention period of no more than 28 days.

Another user may send a "Mazal tov" message. It contains sender and recipient identifiers, the sender's name if published, the idea identifier and the message text. Only sender and recipient may read it. It is deleted after delivery to the local journal and is intended for TTL deletion after no more than 90 days.

## 7. Community tips

If you submit a tip, its text, your profile name, account identifier and review status are stored. Approved tips are visible to signed-in users. Support administrators review, approve or reject them. Your tips are deleted when your account is deleted.

## 8. Support requests

If you send a problem or idea, we store the text, request type, your name and account identifier, device model, operating system, app version, submission time and any image you attach. Replies from you and the Shadchan team are kept in a thread. Only you and authorised support administrators can read the request and thread.

Support correspondence is retained while needed to handle the request, document a defect, secure the service and prevent abuse. It is not deleted automatically with the account; this is also stated in the deletion confirmation. You may request earlier deletion at **giladsh22@gmail.com**, subject to any legal retention requirement.

## 9. App Check and service security

Firebase App Check sends attestation material and tokens to Google or Apple to verify genuine installations. Firebase states that App Check does not retain attestation material; tokens are time-limited, and tokens used with replay protection may be kept for up to 30 days. App Check is not used to identify database content.

## 10. Information website

The static website on Firebase Hosting has no accounts, forms, cookies, advertising or analytics. Firebase Hosting and Google may process technical connection information, such as IP address and user-agent, to deliver pages, secure the service and prevent abuse under Google's terms.

## 11. Permissions

The Application may request contacts, photos/media and notifications only when the related feature is used. You may revoke a permission in device settings, although the dependent feature may stop working.

## 12. Providers and international transfers

The Application uses Google's Firebase Authentication, Cloud Firestore, Cloud Storage, Firebase App Check, Firebase AI Logic/Vertex AI and Firebase Hosting; Google Sign-In, Google ML Kit and store services; and Sign in with Apple on Apple devices. Each provider has its own terms and privacy policy.

Information may be processed outside your country. Firebase Authentication operates from US data centres; global and AI services may process data in other locations. Where required, we rely on Google data-processing agreements and transfer mechanisms and other lawful safeguards.

## 13. Retention and erasure

- Local data remains until you delete it, delete the account or uninstall the Application.
- Backup remains until erased from the privacy screen or through account deletion. Uninstalling alone does not erase it.
- Community data can be erased immediately from the privacy screen.
- Engagement records and congratulations follow section 6.
- Your tips are erased with the account.
- Support correspondence follows section 8.
- Firebase Authentication may keep logged IP addresses for a few weeks. Firebase states that after user deletion, Authentication data is removed from live and backup systems within 180 days.

## 14. Account deletion

Account deletion can be completed inside the Application: **My profile → Account → Delete account and data**. The Application asks you to reauthenticate with Apple, Google or your password. For an Apple-linked account, it obtains a fresh authorization code and sends it to Firebase to revoke Apple tokens before deleting the user.

Deletion removes the Firebase user, cloud backup and photographs, community data and public avatar, engagement announcements, pending congratulations and tips, then clears the local database. It cannot be undone. Support correspondence follows section 8, and exported files or information shared outside the Application remain outside our control.

If you no longer have access to the Application, request deletion at **giladsh22@gmail.com**. We will verify ownership first.

## 15. Rights and legal bases

Depending on applicable law, processing necessary to run the account and Application is based on performance of the service; permissions, AI and voluntary publication rely on consent; and security, support and community operations may rely on legitimate interests. You may have rights of access, correction, erasure, restriction, objection, portability and withdrawal of consent, and the right to complain to a supervisory authority. We do not sell or "share" personal information for cross-context behavioural advertising under the CCPA/CPRA.

You are responsible for information about other people that you enter, including having a lawful basis to keep and share it. Use the Application as you would want someone to use information about you.

## 16. Children

The Application is not intended for children under 16, or a higher age required by local law, and we do not knowingly collect information from children.

## 17. Security

We use operating-system protections, Firebase Security Rules, uid separation, App Check and encrypted transport. No system is completely secure. You are also responsible for securing the device, sign-in provider account and exported files.

## 18. Changes and contact

A material change will carry a new update date and be presented where required. For questions, rights requests or deletion requests: **Gilad Shtruzman — giladsh22@gmail.com**.

If the English translation differs from the Hebrew policy, the Hebrew policy prevails.
