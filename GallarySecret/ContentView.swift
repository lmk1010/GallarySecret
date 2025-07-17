//
//  ContentView.swift
//  GallarySecret
//
//  Created by 刘明康 on 2025/4/10.
//

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @State private var showMembership = false
    
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
            }
            .padding()
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(showMembership: $showMembership)
            }
            .sheet(isPresented: $showMembership) {
                MembershipView()
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var showMembership: Bool
    @State private var showPasswordSettings = false
    @State private var showPrivacyPolicy = false
    @ObservedObject private var storeManager = StoreKitManager.shared
    @State private var showRestoreAlert = false
    @State private var restoreAlertMessage = ""
    @State private var restoreAlertTitle = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Security")) {
                    Button(action: {
                        showPasswordSettings = true
                    }) {
                        HStack {
                            Text("Set Password")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("Membership")) {
                    Button(action: {
                        showMembership = true
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Text("Upgrade to Premium")
                            Spacer()
                            if storeManager.isMember {
                                Text("Active")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // 恢复购买按钮 - 只在用户不是会员时显示
                    if !storeManager.isMember {
                        Button(action: {
                            Task {
                                await restorePurchases()
                            }
                        }) {
                            HStack {
                                Label("Restore Purchases", systemImage: "arrow.clockwise")
                                Spacer()
                                if storeManager.isRestoringPurchases {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                }
                            }
                            .foregroundColor(storeManager.isRestoringPurchases ? .gray : (storeManager.isAppleIDSignedIn ? .blue : .gray))
                        }
                        .disabled(storeManager.isRestoringPurchases || !storeManager.isAppleIDSignedIn)
                    }
                }
                
                Section(header: Text("About")) {
                    Button(action: {
                        showPrivacyPolicy = true
                    }) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(
                leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .sheet(isPresented: $showPasswordSettings) {
                PasswordSettingsView()
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .alert(restoreAlertTitle, isPresented: $showRestoreAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(restoreAlertMessage)
            }
            .onReceive(storeManager.$restoreSuccess) { success in
                if success {
                    restoreAlertTitle = "Restore Successful"
                    restoreAlertMessage = "Your purchase has been successfully restored, you can now enjoy all premium features."
                    showRestoreAlert = true
                    storeManager.restoreSuccess = false
                }
            }
            .onReceive(storeManager.$restoreError) { error in
                if let error = error {
                    restoreAlertTitle = "Restore Failed"
                    restoreAlertMessage = error
                    showRestoreAlert = true
                    storeManager.restoreError = nil
                }
            }
        }
    }
    
    private func restorePurchases() async {
        print("SettingsView: Starting restore purchases...")
        await storeManager.restorePurchases()
    }
}

#Preview {
    ContentView()
}
