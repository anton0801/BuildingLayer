//
//  SyncSettingsView.swift
//  BuildLayer
//
//  The cloud-backup section of Settings.
//
//  Note what is absent: there is no field for a server address, and no way to
//  point the app anywhere other than the build's compiled-in endpoint.
//

import SwiftUI

struct SyncSettingsCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @ObservedObject var sync: SyncEngine

    @State private var showTransferCode = false
    @State private var showRedeem = false
    @State private var showDeleteAlert = false

    var body: some View {
        BLCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: Icon.cloud).font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.primary)
                    Text("Cloud Backup").font(.bl(16, .heavy)).foregroundColor(Theme.cardText)
                    Spacer()
                    statusDot
                }

                statusLine

                Toggle(isOn: Binding(
                    get: { sync.syncEnabled },
                    set: { on in
                        sync.syncEnabled = on
                        if on { sync.start() }
                        appState.haptic()
                    })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Back up my projects").font(.bl(15, .bold)).foregroundColor(Theme.cardText)
                        Text("Your work is saved on this device either way. Backup adds a copy on the server so it survives losing the phone.")
                            .font(.bl(11, .medium)).foregroundColor(Theme.cardSubtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))

                if sync.syncEnabled {
                    if sync.pendingChanges > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: Icon.clock).font(.system(size: 11, weight: .bold))
                            Text("\(sync.pendingChanges) change\(sync.pendingChanges == 1 ? "" : "s") waiting to upload")
                                .font(.bl(12, .semibold))
                        }.foregroundColor(Theme.cardSubtext)
                    }

                    GhostButton(title: sync.status.isBusy ? "Syncing…" : "Sync now",
                                icon: Icon.refresh, tint: Theme.layer) {
                        appState.haptic()
                        sync.syncNow(force: true)
                    }
                    .disabled(sync.status.isBusy)

                    Divider().background(Theme.cardBorder)

                    // The answer to the obvious weakness of an anonymous
                    // account: without this, reinstalling loses everything.
                    Text("MOVING TO A NEW PHONE").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                    Text("Your projects are tied to this install, not to an email. Generate a code here, type it on the new phone, and everything moves across.")
                        .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        SecondaryButton(title: "Get code", icon: Icon.arrowUpR) {
                            appState.haptic(); showTransferCode = true
                        }
                        GhostButton(title: "I have a code", icon: Icon.arrowR, tint: Theme.layer) {
                            appState.haptic(); showRedeem = true
                        }
                    }

                    Divider().background(Theme.cardBorder)

                    GhostButton(title: "Remove my data from the server", icon: Icon.trash, tint: Theme.fail) {
                        showDeleteAlert = true
                    }
                    Text("Deletes the server copy only. Everything on this device stays where it is.")
                        .font(.bl(10, .medium)).foregroundColor(Theme.cardInactive)
                }
            }
        }
        .sheet(isPresented: $showTransferCode) {
            TransferCodeSheet(sync: sync).environmentObject(appState).environmentObject(toast)
        }
        .sheet(isPresented: $showRedeem) {
            RedeemCodeSheet(sync: sync).environmentObject(appState).environmentObject(toast)
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(title: Text("Remove the server copy?"),
                  message: Text("Your projects stay on this phone. The backup is deleted and cannot be recovered."),
                  primaryButton: .destructive(Text("Remove")) {
                      sync.deleteServerData { result in
                          switch result {
                          case .success:
                              toast.flash("Server copy removed", icon: Icon.check)
                          case .failure(let error):
                              toast.flash(error.localizedDescription, icon: Icon.warning)
                          }
                      }
                  },
                  secondaryButton: .cancel())
        }
    }

    private var statusDot: some View {
        let color: Color
        switch sync.status {
        case .idle:          color = Theme.pass
        case .syncing:       color = Theme.progress
        case .offline:       color = Theme.warn
        case .failed:        color = Theme.fail
        case .notRegistered: color = Theme.cardInactive
        }
        return Circle().fill(color).frame(width: 9, height: 9)
    }

    @ViewBuilder private var statusLine: some View {
        switch sync.status {
        case .syncing:
            Text("Syncing…").font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
        case .offline:
            Text("Offline — your work is saved here and will upload when you reconnect.")
                .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message).font(.bl(12, .semibold)).foregroundColor(Theme.fail)
                .fixedSize(horizontal: false, vertical: true)
        case .notRegistered:
            Text(sync.needsReregistration
                 ? "This device was signed out — most likely its account moved to another phone."
                 : "Not backed up yet.")
                .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            if let date = sync.lastSyncedAt {
                Text("Last backed up \(relativeTimeText(date))")
                    .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
            } else {
                Text("Ready to back up.").font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
            }
        }
    }
}

// MARK: - Generating a transfer code

struct TransferCodeSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var sync: SyncEngine

    @State private var code: String?
    @State private var errorText: String?
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        BLCard {
                            VStack(spacing: 14) {
                                if isLoading {
                                    Text("Generating…").font(.bl(15, .bold)).foregroundColor(Theme.cardSubtext)
                                        .padding(.vertical, 30)
                                } else if let code = code {
                                    Text("TYPE THIS ON THE NEW PHONE")
                                        .font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                                    Text(formatted(code))
                                        .font(.system(size: 34, weight: .heavy, design: .monospaced))
                                        .foregroundColor(Theme.cardText)
                                        .minimumScaleFactor(0.5).lineLimit(1)
                                    Text("Valid for 10 minutes, and only once.")
                                        .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                                } else {
                                    Text(errorText ?? "Could not generate a code.")
                                        .font(.bl(14, .semibold)).foregroundColor(Theme.fail)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 20)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }.padding(.horizontal, 18)

                        BLCard(tint: Theme.cardBlue) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: Icon.warning).foregroundColor(Theme.warn)
                                Text("Once the new phone uses this code, this phone stops syncing and its projects stay here as a local copy.")
                                    .font(.bl(12, .semibold)).foregroundColor(Theme.cardText)
                            }
                        }.padding(.horizontal, 18)
                    }
                    .padding(.top, 14)
                }
            }
            .navigationBarTitle("Transfer Code", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") { presentationMode.wrappedValue.dismiss() }
                                    .foregroundColor(Theme.primary).font(.bl(15, .bold)))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: load)
    }

    private func load() {
        guard code == nil else { return }
        sync.requestTransferCode { result in
            isLoading = false
            switch result {
            case .success(let payload): code = payload.code
            case .failure(let error):   errorText = error.localizedDescription
            }
        }
    }

    /// Grouped in threes — a 9-digit run is near-impossible to read back aloud.
    private func formatted(_ raw: String) -> String {
        let digits = Array(raw)
        guard digits.count == 9 else { return raw }
        return String(digits[0..<3]) + " " + String(digits[3..<6]) + " " + String(digits[6..<9])
    }
}

// MARK: - Redeeming a transfer code

struct RedeemCodeSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var sync: SyncEngine

    @State private var entry = ""
    @State private var errorText: String?
    @State private var isWorking = false
    @State private var showConfirm = false

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        BLCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Enter the 9-digit code shown on your old phone.")
                                    .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                    .fixedSize(horizontal: false, vertical: true)
                                BLField(label: "Transfer code", placeholder: "123 456 789",
                                        text: $entry, keyboard: .numberPad)
                                if let errorText = errorText {
                                    Text(errorText).font(.bl(12, .semibold)).foregroundColor(Theme.fail)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                PrimaryButton(title: isWorking ? "Transferring…" : "Transfer my projects",
                                              icon: Icon.arrowR) {
                                    showConfirm = true
                                }
                            }
                        }.padding(.horizontal, 18)

                        BLCard(tint: Theme.cardBlue) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: Icon.warning).foregroundColor(Theme.fail)
                                Text("Anything currently in this app is replaced by the projects from the other phone. If you have work here that is not backed up, export it first.")
                                    .font(.bl(12, .semibold)).foregroundColor(Theme.cardText)
                            }
                        }.padding(.horizontal, 18)
                    }
                    .padding(.top, 14)
                }
            }
            .navigationBarTitle("Transfer In", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                                    .foregroundColor(Theme.subtitle).font(.bl(15, .semibold)))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert(isPresented: $showConfirm) {
            Alert(title: Text("Replace everything in this app?"),
                  message: Text("This phone's current projects will be removed and replaced by the ones being transferred."),
                  primaryButton: .destructive(Text("Replace")) { redeem() },
                  secondaryButton: .cancel())
        }
    }

    private func redeem() {
        let digits = entry.filter { $0.isNumber }
        guard digits.count == 9 else {
            errorText = "The code is 9 digits."
            return
        }
        isWorking = true
        errorText = nil
        sync.redeemTransferCode(digits) { result in
            isWorking = false
            switch result {
            case .success:
                appState.haptic(.medium)
                toast.flash("Projects transferred", icon: Icon.check)
                presentationMode.wrappedValue.dismiss()
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }
}
