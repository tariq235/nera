// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Generated from the WebAuthn shim source; edit the script here (it's compiled into the renderer helper,
// because the sandboxed renderer can't read files). See docs/security/passkeys.md.
#pragma once

static const char kNeraWebAuthnShim[] = R"NERAJS(
// Nera WebAuthn bridge for the Chromium engine (FEAT-027, docs/security/passkeys.md).
// Installed by the renderer helper before any page script runs. `bridge(kind, json)` returns a Promise and is
// only reachable from this closure. The browser process takes the origin from the frame, never from the page.
// `passkeys`: an authenticator is available. Without one, PublicKeyCredential stays absent (sites show their
// password sign-in), but WebAuthn calls still go through Nera so they fail fast instead of hanging.
(function (bridge, passkeys) {
  'use strict';
  if (!window.isSecureContext || !navigator.credentials) return;

  const b64 = (buf) => {
    const bytes = buf instanceof ArrayBuffer ? new Uint8Array(buf) : new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
    let s = '';
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  const unb64 = (str) => {
    const s = atob(str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4));
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out.buffer;
  };
  const isBuffer = (v) => v instanceof ArrayBuffer || ArrayBuffer.isView(v);
  const encode = (v) => {
    if (isBuffer(v)) return { $b64: b64(v) };
    if (Array.isArray(v)) return v.map(encode);
    if (v && typeof v === 'object') {
      const o = {};
      for (const k of Object.keys(v)) o[k] = encode(v[k]);
      return o;
    }
    return v;
  };
  const fail = (name, message) => { const e = new DOMException(message, name); return Promise.reject(e); };

  const makeCredential = (r) => {
    const response = { clientDataJSON: unb64(r.clientDataJSON) };
    if (r.attestationObject) {
      response.attestationObject = unb64(r.attestationObject);
      response.getTransports = () => r.transports || ['internal', 'hybrid'];
      response.getAuthenticatorData = () => (r.authenticatorData ? unb64(r.authenticatorData) : new ArrayBuffer(0));
      response.getPublicKey = () => null;
      response.getPublicKeyAlgorithm = () => (r.publicKeyAlgorithm ?? -7);
    } else {
      response.authenticatorData = unb64(r.authenticatorData);
      response.signature = unb64(r.signature);
      response.userHandle = r.userHandle ? unb64(r.userHandle) : null;
    }
    const credential = {
      id: r.id, rawId: unb64(r.id), type: 'public-key', response,
      authenticatorAttachment: r.authenticatorAttachment || 'platform',
      getClientExtensionResults: () => r.clientExtensionResults || {},
      toJSON: () => r,
    };
    if (typeof PublicKeyCredential === 'function') Object.setPrototypeOf(credential, PublicKeyCredential.prototype);
    return credential;
  };

  const call = (kind, publicKey, signal) => {
    if (signal && signal.aborted) return fail('AbortError', 'The operation was aborted.');
    return bridge(kind, JSON.stringify(encode(publicKey))).then(
      (json) => makeCredential(JSON.parse(json)),
      (err) => {
        // The bridge rejects with "Name|message" (native code can only reject with a string).
        const s = String((err && err.message) || err);
        const i = s.indexOf('|');
        throw new DOMException(i > 0 ? s.slice(i + 1) : s, i > 0 ? s.slice(0, i) : 'NotAllowedError');
      },
    );
  };

  const nativeCreate = navigator.credentials.create.bind(navigator.credentials);
  const nativeGet = navigator.credentials.get.bind(navigator.credentials);
  Object.defineProperty(navigator.credentials, 'create', {
    value: function create(options) {
      if (options && options.publicKey) return call('create', options.publicKey, options.signal);
      return nativeCreate(options);
    },
  });
  Object.defineProperty(navigator.credentials, 'get', {
    value: function get(options) {
      if (options && options.publicKey) {
        if (options.mediation === 'conditional') return new Promise(() => {});  // passkey autofill: not offered yet
        return call('get', options.publicKey, options.signal);
      }
      return nativeGet(options);
    },
  });
  const replace = (target, name, value) => {
    try {
      Object.defineProperty(target, name, { value, writable: true, configurable: true });
    } catch (e) {
      try { target[name] = value; } catch (e2) { /* leave the original */ }
    }
  };
  if (!passkeys) return;
  // Blink installs its own PublicKeyCredential when the document is set up, after this context exists. The
  // parser runs pending microtasks (MutationObserver callbacks) before it executes any page script, so patch
  // on the first DOM insertion: after Blink, before the page.
  const installPublicKeyCredential = () => {
    if (typeof PublicKeyCredential !== 'function') {
      // Embedded Chromium doesn't expose the interface; provide it so sites can feature-detect passkeys.
      const PKC = function PublicKeyCredential() { throw new TypeError('Illegal constructor'); };
      Object.defineProperty(window, 'PublicKeyCredential', { value: PKC, writable: true, configurable: true });
    }
    replace(PublicKeyCredential, 'isUserVerifyingPlatformAuthenticatorAvailable',
      () => bridge('available', '{}').then((v) => v === 'true', () => false));
    replace(PublicKeyCredential, 'isConditionalMediationAvailable', () => Promise.resolve(false));
    replace(PublicKeyCredential, 'getClientCapabilities', () => Promise.resolve({
      conditionalCreate: false, conditionalGet: false, hybridTransport: true, passkeyPlatformAuthenticator: true,
      userVerifyingPlatformAuthenticator: true, relatedOrigins: false, signalAllAcceptedCredentials: false,
      signalCurrentUserDetails: false, signalUnknownCredential: false,
    }));
    const fromJSON = (o) => {
      const out = { ...o, challenge: unb64(o.challenge) };
      if (o.user) out.user = { ...o.user, id: unb64(o.user.id) };
      for (const k of ['excludeCredentials', 'allowCredentials']) {
        if (o[k]) out[k] = o[k].map((c) => ({ ...c, id: unb64(c.id) }));
      }
      return out;
    };
    replace(PublicKeyCredential, 'parseCreationOptionsFromJSON', fromJSON);
    replace(PublicKeyCredential, 'parseRequestOptionsFromJSON', fromJSON);
  };
  let installed = false;
  const installOnce = () => {
    if (installed) return;
    installed = true;
    installPublicKeyCredential();
  };
  const observer = new MutationObserver(() => {
    observer.disconnect();
    installOnce();
  });
  observer.observe(document, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', installOnce, { once: true, capture: true });
})
)NERAJS";
