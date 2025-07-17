import SwiftUI

struct PasswordSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var storeManager = StoreKitManager.shared
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var showMembership = false
    
    var body: some View {
        NavigationView {
            Form {
                // 会员状态显示
                Section(header: Text("Membership Status")) {
                    HStack {
                        Image(systemName: storeManager.isMember ? "crown.fill" : "crown")
                            .foregroundColor(storeManager.isMember ? .orange : .gray)
                        Text(storeManager.isMember ? "Premium Member" : "Regular User")
                            .font(.headline)
                            .foregroundColor(storeManager.isMember ? .orange : .gray)
                        Spacer()
                        if storeManager.isMember {
                            Text("✓")
                                .foregroundColor(.green)
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 密码设置区域
                Section(header: Text("Password Settings")) {
                    if storeManager.isMember {
                        // 会员可以修改密码
                        VStack(alignment: .leading, spacing: 16) {
                            Text("As a premium member, you can customize your password")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.bottom, 8)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("New Password")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    SecureField("Enter 4-20 digit password", text: $newPassword)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .disabled(!storeManager.isMember)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Confirm Password")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    SecureField("Enter password again", text: $confirmPassword)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .disabled(!storeManager.isMember)
                                }
                            }
                            .padding(.vertical, 8)
                            
                            Button("Save Password") {
                                savePassword()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(!storeManager.isMember)
                        }
                        .padding(.vertical, 8)
                    } else {
                        // 普通用户显示限制信息
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.gray)
                                Text("Default Password: 1234")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Regular User Limitations")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                        .fontWeight(.semibold)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 6))
                                        Text("Can only use default password 1234")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 6))
                                        Text("Upgrade to premium to customize password")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 12)
                            
                            Button("Upgrade to Premium") {
                                showMembership = true
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .controlSize(.large)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Password Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("Password set successfully")
            }
            .sheet(isPresented: $showMembership) {
                MembershipView()
            }
        }
    }
    
    private func savePassword() {
        // 再次确认用户是会员
        guard storeManager.isMember else {
            errorMessage = "Only premium members can change password"
            showError = true
            return
        }
        
        // 验证密码
        guard !newPassword.isEmpty else {
            errorMessage = "Please enter new password"
            showError = true
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        guard newPassword.count >= 4 && newPassword.count <= 20 else {
            errorMessage = "Password must be between 4-20 digits"
            showError = true
            return
        }
        
        guard newPassword.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Password can only contain numbers"
            showError = true
            return
        }
        
        // 保存密码到 UserDefaults
        UserDefaults.standard.set(newPassword, forKey: "computerPassword")
        showSuccess = true
    }
}

#Preview {
    PasswordSettingsView()
} 