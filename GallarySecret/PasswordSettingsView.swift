import SwiftUI

struct PasswordSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("新密码")) {
                    SecureField("请输入新密码", text: $newPassword)
                        .keyboardType(.numberPad)
                    SecureField("确认新密码", text: $confirmPassword)
                        .keyboardType(.numberPad)
                }
                
                Section(footer: Text("密码必须为4-20位纯数字")) {
                    Button("保存") {
                        savePassword()
                    }
                }
            }
            .navigationTitle("设置计算器密码")
            .navigationBarItems(
                leading: Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("成功", isPresented: $showSuccess) {
                Button("确定") {
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("密码设置成功")
            }
        }
    }
    
    private func savePassword() {
        // 验证密码
        guard !newPassword.isEmpty else {
            errorMessage = "请输入新密码"
            showError = true
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            showError = true
            return
        }
        
        guard newPassword.count >= 4 && newPassword.count <= 20 else {
            errorMessage = "密码长度必须在4-20位之间"
            showError = true
            return
        }
        
        guard newPassword.allSatisfy({ $0.isNumber }) else {
            errorMessage = "密码必须为纯数字"
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