// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Chromium child process for Nera (renderer, GPU, network/storage utilities, plugin, alerts).
// Order matters on macOS: enter Chromium's sandbox first, then load the framework, then hand over to CEF.
// Written for Nera against CEF's public API.
//
// Renderer only: installs Nera's WebAuthn bridge (webauthn_shim.h) in every new script context, before page
// scripts run. Requests go to the browser process as "nera.webauthn"; answers come back as
// "nera.webauthn.result". The browser process decides the origin from the frame (docs/security/passkeys.md).
#include <map>
#include <string>

#include "include/cef_app.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_sandbox_mac.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_library_loader.h"
#include "webauthn_shim.h"

namespace {

struct Pending {
    CefRefPtr<CefV8Context> context;
    CefRefPtr<CefV8Value> promise;
};

/// Browsers whose pages may see PublicKeyCredential (an authenticator is available), by browser id.
std::map<int, bool>& PasskeyBrowsers() {
    static std::map<int, bool> browsers;
    return browsers;
}

std::map<int, Pending>& PendingRequests() {
    static std::map<int, Pending> pending;
    return pending;
}

/// `bridge(kind, json)` → Promise; reachable only from the shim's closure.
class Bridge : public CefV8Handler {
   public:
    bool Execute(const CefString&, CefRefPtr<CefV8Value>, const CefV8ValueList& args, CefRefPtr<CefV8Value>& retval,
                 CefString& exception) override {
        if (args.size() != 2 || !args[0]->IsString() || !args[1]->IsString()) {
            exception = "bad arguments";
            return true;
        }
        CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
        CefRefPtr<CefV8Value> promise = CefV8Value::CreatePromise();
        static int next = 0;
        const int id = ++next;
        PendingRequests()[id] = Pending{context, promise};
        CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("nera.webauthn");
        message->GetArgumentList()->SetInt(0, id);
        message->GetArgumentList()->SetString(1, args[0]->GetStringValue());
        message->GetArgumentList()->SetString(2, args[1]->GetStringValue());
        context->GetFrame()->SendProcessMessage(PID_BROWSER, message);
        retval = promise;
        return true;
    }
    IMPLEMENT_REFCOUNTING(Bridge);
};

class HelperApp : public CefApp, public CefRenderProcessHandler {
   public:
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }

    void OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> extra) override {
        PasskeyBrowsers()[browser->GetIdentifier()] = extra && extra->GetBool("nera.passkeys");
    }

    void OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) override { PasskeyBrowsers().erase(browser->GetIdentifier()); }

    void OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, CefRefPtr<CefV8Context> context) override {
        CefRefPtr<CefV8Value> install;
        CefRefPtr<CefV8Exception> error;
        if (!context->Eval(kNeraWebAuthnShim, "", 0, install, error) || !install || !install->IsFunction()) return;
        const bool passkeys = PasskeyBrowsers()[browser->GetIdentifier()];
        CefV8ValueList args = {CefV8Value::CreateFunction("bridge", new Bridge()), CefV8Value::CreateBool(passkeys)};
        install->ExecuteFunctionWithContext(context, nullptr, args);
    }

    void OnContextReleased(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefV8Context> context) override {
        auto& pending = PendingRequests();
        for (auto it = pending.begin(); it != pending.end();) {
            it = it->second.context->IsSame(context) ? pending.erase(it) : std::next(it);
        }
    }

    bool OnProcessMessageReceived(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefProcessId,
                                  CefRefPtr<CefProcessMessage> message) override {
        if (message->GetName() == "nera.eval") return Evaluate(frame, message);
        if (message->GetName() != "nera.webauthn.result") return false;
        CefRefPtr<CefListValue> args = message->GetArgumentList();
        auto& pending = PendingRequests();
        auto it = pending.find(args->GetInt(0));
        if (it == pending.end()) return true;
        Pending request = it->second;
        pending.erase(it);
        if (!request.context->IsValid() || !request.context->Enter()) return true;
        if (args->GetBool(1)) {
            request.promise->ResolvePromise(CefV8Value::CreateString(args->GetString(2)));
        } else {
            request.promise->RejectPromise(args->GetString(2));
        }
        request.context->Exit();
        return true;
    }

   private:
    /// Runs one of Nera's scripts (sent by the browser process, never by a page) in the frame and sends its
    /// result back as a string: strings as they are, everything else as JSON.
    static bool Evaluate(CefRefPtr<CefFrame> frame, CefRefPtr<CefProcessMessage> message) {
        CefRefPtr<CefListValue> args = message->GetArgumentList();
        CefRefPtr<CefProcessMessage> reply = CefProcessMessage::Create("nera.eval.result");
        reply->GetArgumentList()->SetInt(0, args->GetInt(0));
        reply->GetArgumentList()->SetBool(1, false);
        CefRefPtr<CefV8Context> context = frame ? frame->GetV8Context() : nullptr;
        if (context && context->Enter()) {
            const std::string wrapped = "(() => { const v = (" + args->GetString(1).ToString() +
                                        "); return typeof v === 'string' ? v : JSON.stringify(v ?? null); })()";
            CefRefPtr<CefV8Value> value;
            CefRefPtr<CefV8Exception> error;
            if (context->Eval(wrapped, "", 0, value, error) && value && value->IsString()) {
                reply->GetArgumentList()->SetBool(1, true);
                reply->GetArgumentList()->SetString(2, value->GetStringValue());
            }
            context->Exit();
        }
        if (frame) frame->SendProcessMessage(PID_BROWSER, reply);
        return true;
    }

    IMPLEMENT_REFCOUNTING(HelperApp);
};

}  // namespace

int main(int argc, char* argv[]) {
    CefScopedSandboxContext sandbox_context;
    if (!sandbox_context.Initialize(argc, argv)) return 1;
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInHelper()) return 1;
    CefMainArgs main_args(argc, argv);
    CefRefPtr<HelperApp> app = new HelperApp();
    return CefExecuteProcess(main_args, app, nullptr);
}
