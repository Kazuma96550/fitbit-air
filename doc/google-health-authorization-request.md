# Draft authorization request

Prepared for the developer to send through Google Health support or the relevant
Play Console policy-support channel. This draft has not been sent. Support may
need to route it to a team able to address third-party device integrations;
a reply is not a guarantee of Play approval.

Subject: Authorization and Google Play requirements for an independent local Fitbit Air companion

Hello,

We are developing Air Relay, an independent Android companion that lets a user
relay selected phone notifications as vibrations on their own Fitbit Air. The
Air is already paired to that phone through Google Health. The user explicitly
grants Android notification access and Bluetooth permissions and starts/stops
the relay through visible controls.

The app uses a local BLE/Gattlink/DTLS connection. Battery and vibration settings
are accessed through the firmware's bootstrap session (`/md/606` and
`/settings`). The app does not obtain Google account tokens, extract the
per-device credential from Google Health's private storage, or use Google Health
cloud APIs. The vibration mechanism changes settings that produce pulses; it
is not the credential-protected native notification-record endpoint.

There are two implementation details we want to resolve before Play submission:

1. The experimental implementation executes `libxp.so` copied from the publicly
   installed, signature-verified Google Health APK into our own private code
   cache. We are investigating replacement with our own build of the publicly
   Apache-licensed Golden Gate source, packaged with our application. Please
   clarify whether the current copied-library arrangement is licensed and
   acceptable for Play distribution; we are not assuming that it is.
2. The tracker has a shared channel. Our session requires a handoff so Google
   Health can resume synchronization. The experimental recovery starts a fresh
   handshake and declines an identity for which we do not have a key; the
   observed tracker reset permits Google Health to re-establish its session.
   Please clarify whether this is acceptable and whether there is a supported
   coexistence mechanism we should use instead.

Does this local, user-authorized companion qualify as an Authorized Connection
under the current Google Health Additional Terms? If explicit approval is
required, which team or process can grant it? Would packaging a source-built
transport address the native-code-loading concern, and are there other
requirements for publishing this functionality on Google Play?

We can provide source code, a data-flow description and a recording of the
on-device behavior for review. We will accurately describe the app as an
independent companion and disclose all notification processing to users.

Thank you.
