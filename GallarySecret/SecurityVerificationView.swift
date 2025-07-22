import SwiftUI
import LocalAuthentication

struct SecurityVerificationView: View {
    let onAuthenticated: () -> Void
    
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isBiometricAvailable = false
    @Environment(\.colorScheme) var colorScheme
    
    // 从 UserDefaults 获取密码
    private var correctPassword: String {
        UserDefaults.standard.string(forKey: "computerPassword") ?? "1234"
    }
    
    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                gradient: Gradient(colors: [
                    colorScheme == .dark ? Color.black : Color.blue.opacity(0.1),
                    colorScheme == .dark ? Color.gray.opacity(0.3) : Color.blue.opacity(0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // 应用图标和标题
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.3), radius: 10)
                    
                    Text("Private Photo Gallery")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                    
                    Text("Secure your precious memories")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // 验证区域
                VStack(spacing: 25) {
                    // 生物识别验证按钮
                    if isBiometricAvailable {
                        Button(action: authenticateWithBiometrics) {
                            HStack {
                                Image(systemName: getBiometricIcon())
                                    .font(.title2)
                                Text(getBiometricText())
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(15)
                            .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 3)
                        }
                        .padding(.horizontal, 40)
                        
                        Text("or")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    
                    // 密码输入
                    VStack(spacing: 15) {
                        SecureField("Enter Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.title3)
                            .frame(height: 50)
                            .padding(.horizontal, 40)
                            .onSubmit {
                                verifyPassword()
                            }
                        
                        Button(action: verifyPassword) {
                            Text("Unlock")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.green)
                                .cornerRadius(15)
                                .shadow(color: .green.opacity(0.3), radius: 5, x: 0, y: 3)
                        }
                        .padding(.horizontal, 40)
                        .disabled(password.isEmpty)
                    }
                }
                
                Spacer()
                
                // 底部提示
                VStack(spacing: 10) {
                    Text("Your photos are protected with end-to-end encryption")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("Secure & Private")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            checkBiometricAvailability()
            // 如果支持生物识别，自动尝试验证
            if isBiometricAvailable {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    authenticateWithBiometrics()
                }
            }
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                password = ""
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        isBiometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    private func getBiometricIcon() -> String {
        let context = LAContext()
        if context.biometryType == .faceID {
            return "faceid"
        } else if context.biometryType == .touchID {
            return "touchid"
        } else {
            return "person.fill.checkmark"
        }
    }
    
    private func getBiometricText() -> String {
        let context = LAContext()
        if context.biometryType == .faceID {
            return "Unlock with Face ID"
        } else if context.biometryType == .touchID {
            return "Unlock with Touch ID"
        } else {
            return "Unlock with Biometrics"
        }
    }
    
    private func authenticateWithBiometrics() {
        let context = LAContext()
        let reason = "Unlock your private photo gallery"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    onAuthenticated()
                } else if let error = error {
                    let laError = error as! LAError
                    switch laError.code {
                    case .userCancel, .userFallback, .systemCancel:
                        // 用户取消，不显示错误
                        break
                    default:
                        errorMessage = "Biometric authentication failed. Please try again or use password."
                        showError = true
                    }
                }
            }
        }
    }
    
    private func verifyPassword() {
        if password == correctPassword {
            onAuthenticated()
        } else {
            errorMessage = "Incorrect password. Please try again."
            showError = true
            password = ""
        }
    }
}

#Preview {
    SecurityVerificationView(onAuthenticated: {})
}