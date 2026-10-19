# Google Play feasibility review

Reviewed 2026-10-19 against application commit `64c9c0e` and upstream Golden
Gate commit `b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa`.

## Decision

The current application is not cleared for a public Play release by this
review. Removing message-tone analysis does not resolve the native dependency,
protocol authorization, or shared-channel behavior. A self-built open-source
transport is a credible engineering direction, but has not been compiled or
verified on the Air as part of this review. Store acceptance and applicable
legal rights remain separate questions.

This is a static source and published-policy review, not a legal determination,
a Google approval, or a device-validation result. No account credentials were
accessed, no support requests were sent, and no application behavior was changed.

## Confirmed implementation facts

| Area | Evidence | Consequence |
| --- | --- | --- |
| Native loading | `GoogleHealthNativeLoader.initialize` checks Google Health's signing lineage, extracts `libxp.so` from its installed APK, caches it privately, then calls `GoldenGate.init` / `System.load`. | The project does not ship that binary, but executes another app's native implementation. Signature verification establishes provenance, not a license grant or Play approval. |
| Credential boundary | The documented bootstrap path reaches settings and battery; research documents that normal paired-device account credentials are not obtained. | This is distinct from stealing Google Health's private paired key. It does not establish permission to use the undocumented device interface. |
| Haptics | Settings changes produce pulses; the official notification-command path is not used. | This is an unofficial firmware-dependent mechanism, not an official Fitbit notification SDK. |
| Shared channel | `handOffTrackerChannel` creates a handshake with `RefusingTlsKeyResolver`, observes a tracker reset, then yields to Google Health. | The implementation intentionally affects the shared channel to restore synchronization. This behavior needs its own compatibility and authorization assessment, even after replacing the native library. |
| Tone analysis | `CalendarNotificationListener` calls the local classifier only when enabled; bundled lexicons are used. | Disabling this feature can simplify the first release's data handling, but does not remove notification access or the transport issues. |

Relevant local sources:

- [Native loader](../android/src/main/kotlin/dev/airpulse/fitbit_air/GoogleHealthNativeLoader.kt)
- [Transport and handoff](../android/src/main/kotlin/dev/airpulse/fitbit_air/FitbitAirPlugin.kt)
- [Protocol research](research.md)
- [Third-party notices](../THIRD_PARTY_NOTICES.md)

## Published policy and terms

### Dynamic native code

[Google Play's Device and Network Abuse policy](https://support.google.com/googleplay/android-developer/answer/16559646)
restricts downloading executable code from outside Google Play, unauthorized
access/interference, and service/API use contrary to applicable terms.
Our loader copies from a locally installed application rather than downloading
from a remote server. The published wording does not specifically adjudicate
that arrangement; this review cannot label it automatically forbidden or
approved. [Android's dynamic-code guidance](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)
also distinguishes security mitigations from Play-policy compliance. Bundling
our own licensed, reproducible native build would remove this particular
cross-application code-loading dependency.

### Current Google Health account terms

The [Google Health Additional Terms](https://support.google.com/product-documentation/answer/13511576),
last modified May 19, 2026, expressly include devices and firmware in the service
and describe authorized connections as including approved third-party software.
They direct questions about authorization to support. These are the relevant
additional terms for Google-account users; the separate legacy Fitbit terms
should not be treated as the sole current contract.

The [Google Terms](https://policies.google.com/terms) restrict interference and
certain reverse engineering, subject to applicable-law exceptions, and recognize
that open-source licenses may override portions of the general software terms.
Neither owning the band nor using Apache-licensed transport code alone settles
the authorization question. Applicable interoperability rights require a
jurisdiction-specific assessment. No evidence of Google approval of this app
was established in this review.

### Message reading and separate builds

[Google's User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311)
requires transparent, purpose-limited handling and appropriate disclosure and
consent. Local opt-in classification is not automatically prohibited by the
published policy. The base relay still handles notification data for its app
and conversation rules.

A Play variant without classification and a developer variant with research
tools are reasonable product boundaries. Enforce the Play capability in native
code as well as the UI; persisted settings must not re-enable an omitted
feature. Features must not be concealed from reviewers or activated later to
evade review. See [Behavior Transparency](https://support.google.com/googleplay/android-developer/answer/17006354).

## Source-built replacement assessment

The upstream [Golden Gate source](https://github.com/Google-Health-API/golden-gate/tree/b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa)
has an [Apache-2.0 license](https://github.com/Google-Health-API/golden-gate/blob/b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa/LICENSE).
Its repository includes C transport, Gattlink, CoAP, TLS integration and Android
JNI bindings. It is archived, so maintenance and dependency-security review
would become our responsibility.

Specific evidence for a potential replacement:

- `xp/CMakeLists.txt` includes the Gattlink, CoAP, TLS and stack-builder modules.
- `platform/android/goldengate/GoldenGateBindings/CMakeLists.txt` builds an `xp`
  JNI shared library and links a separately built `libgg` core. Packaging only
  one of them would not reproduce that build arrangement.
- Its JNI source list includes the stack, loop, sink/source and CoAP bridges
  used by the plugin.
- Its stack-builder header exposes configurable RX/TX windows and probe
  parameters, relevant to this project's transport tuning.
- `.gitmodules` names public dependencies including mbedTLS and lwIP. Audit
  selected dependency versions, licenses, notices and security fixes before
  bundling a release.

This is **not a drop-in binary replacement**. Comparing the pinned upstream
`Stack.kt` and JNI source with this repository shows added stack-creation
arguments, a changed creation-result object, and changed native return types
for start/destroy/MTU operations. The existing Kotlin bindings were adapted to
the installed Google Health binary. A source-built backend needs a consistent
Kotlin/JNI interface, with a deliberate port or rollback of those adaptations.

The Apache license on the public source does not establish that the installed
Google Health `libxp.so`, including any additional code in it, has identical
licensing. A reproducible build from the public source is a cleaner provenance
boundary than assuming that binary is covered.

## Required proof before calling a source-built backend viable

1. Pin all selected upstream dependencies and inventory licenses/notices.
2. Define the JNI contract and preserve the transport tuning and error handling
   currently depended on by the plugin.
3. Build the core and JNI libraries on CI or another build machine, package
   them with the app, and initialize without reading Google Health's APK.
4. Verify required Android ABIs and 16 KB page-size support for every native
   library shipped. [Android guidance](https://developer.android.com/guide/practices/page-sizes).
5. On hardware, verify battery read, haptic settings read, single tap,
   double-pulse restore, timeout/cancellation and all cleanup paths.
6. Verify Google Health synchronization during/after operations, both with
   the existing handoff and any candidate replacement. A new native library
   alone does not eliminate the shared-channel reset behavior.
7. Resolve the authorization/terms question independently of technical success.
   Request written clarification from Google Health and qualified advice on
   applicable interoperability rights before treating commercial distribution
   as cleared. A response from support is not a guarantee of Play approval.

## Questions prepared for clarification

- Is a user-authorized companion app permitted to read battery and change
  vibration settings over the Air's bootstrap BLE/Gattlink/DTLS interface,
  without accessing Google account credentials or cloud APIs?
- Is explicit approval required for that local connection under Authorized
  Connections, and is an approval path available?
- Is the shared-channel reset/handoff behavior acceptable, or is there a
  supported way for independent clients to coexist with Google Health?
- Is executing `libxp.so` copied from Google Health's installed APK permitted
  by the relevant license and acceptable for Play distribution? A self-built
  backend would avoid depending on a favorable answer to this question.

## Recommended order

Resolve native-source feasibility and the authorization question before
spending effort on a store submission. Keep experimental phone testing
available while investigating. Build flavors, listing polish and signing can
follow, but do not by themselves address these findings.
