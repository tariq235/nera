# Google Safe Browsing API key

Official Nera releases include an API key for Google Safe Browsing (v5, Local List mode), **restricted to the Safe
Browsing API** in Google Cloud. It's injected when a release is built (from the release environment's secrets) and is
never stored in the repository. Like any key inside a client app it can be extracted, which is why it's restricted
to that one API.

**Building Nera yourself, or a fork:** create your own key: a Google Cloud project, the Safe Browsing API enabled,
and an API key restricted to `safebrowsing.googleapis.com`. Pass it as `NERA_SAFE_BROWSING_KEY` when building
(`make-dmg.sh` and the release workflow read it). Without a key, the build simply can't warn about dangerous sites
(Settings › Privacy says so); WebKit pages still get Apple's own warning.

The Safe Browsing API is for non-commercial use. A commercial product built from Nera should use Google's Web Risk
API instead.

What's sent to Google, and when: [PRIVACY.md](../../PRIVACY.md) and the network inventory in
[docs/security/security-model.md](../security/security-model.md).
