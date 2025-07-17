import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题
                    Text("Privacy Policy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    Text("Last updated: January 2025")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 16)
                    
                    // 引言
                    Text("This is a local photo album app that does not connect to the internet. All your photos are stored locally on your device and never uploaded to any server.")
                        .font(.body)
                        .padding(.bottom, 16)
                    
                    // 1. 信息收集
                    Group {
                        SectionTitle("1. What This App Does")
                        
                        SubSectionTitle("1.1 Local Photo Management")
                        BulletPoint("Creates private photo albums on your device")
                        BulletPoint("All photos remain on your device only")
                        BulletPoint("Uses a password to protect access to the app")
                        BulletPoint("No internet connection required for core functionality")
                        
                        SubSectionTitle("1.2 What We DON'T Do")
                        BulletPoint("We never upload your photos to any server")
                        BulletPoint("We don't collect personal information")
                        BulletPoint("We don't track your usage")
                        BulletPoint("We don't share data with third parties")
                    }
                    
                    // 2. 信息使用
                    Group {
                        SectionTitle("2. How Your Data is Stored")
                        
                        SubSectionTitle("2.1 Local Storage Only")
                        BulletPoint("Photos are copied to the app's private folder on your device")
                        BulletPoint("Album information is stored in a local database")
                        BulletPoint("App settings are stored locally")
                        BulletPoint("Everything stays on your device - nothing goes to the cloud")
                        
                        SubSectionTitle("2.2 Premium Features")
                        BulletPoint("Premium subscription is handled by Apple's App Store")
                        BulletPoint("We only check your subscription status with Apple")
                        BulletPoint("No personal payment information is collected by us")
                    }
                    
                    // 3. 数据存储和安全
                    Group {
                        SectionTitle("3. Security")
                        
                        SubSectionTitle("3.1 Password Protection")
                        BulletPoint("App requires a password to access photos")
                        BulletPoint("Default password is 1234 (can be changed with premium)")
                        BulletPoint("App locks automatically when you switch to other apps")
                        
                        SubSectionTitle("3.2 Device Security")
                        BulletPoint("Photos are protected by your device's built-in security")
                        BulletPoint("Only you can access the app's private folder")
                        BulletPoint("No remote access possible - app works offline only")
                    }
                    
                    // 4. 数据共享
                    Group {
                        SectionTitle("4. No Data Sharing")
                        
                        SubSectionTitle("4.1 Simple Truth")
                        BulletPoint("We cannot share your photos because we never see them")
                        BulletPoint("Everything stays on your device")
                        BulletPoint("No analytics, no tracking, no advertising")
                        BulletPoint("App works completely offline")
                        
                        SubSectionTitle("4.2 Apple Integration Only")
                        BulletPoint("Only connection is to Apple for subscription verification")
                        BulletPoint("This is handled by Apple's secure systems")
                        BulletPoint("We don't see your payment information")
                    }
                    
                    // 5. 您的权利
                    Group {
                        SectionTitle("5. Your Control")
                        
                        SubSectionTitle("5.1 Full Control")
                        BulletPoint("Delete any photo or album anytime")
                        BulletPoint("Uninstall the app to remove everything")
                        BulletPoint("Change password (premium feature)")
                        BulletPoint("Control photo library access in device settings")
                        
                        SubSectionTitle("5.2 No Vendor Lock-in")
                        BulletPoint("Your original photos remain in your photo library")
                        BulletPoint("App only makes copies for organization")
                        BulletPoint("You can export photos back to your photo library")
                    }
                    
                    // 6. 儿童隐私
                    Group {
                        SectionTitle("6. Children's Privacy")
                        Text("Since this app doesn't collect any personal information or connect to the internet, it's safe for all ages. Everything stays on the device.")
                            .font(.body)
                    }
                    
                    // 7. 隐私协议变更
                    Group {
                        SectionTitle("7. Updates")
                        Text("If we update this policy, the new version will be included in app updates. Since the app is offline-only, this is the only way to notify you of changes.")
                            .font(.body)
                    }
                    
                    // 8. 联系我们
                    Group {
                        SectionTitle("8. Contact")
                        Text("Questions about this privacy policy?")
                            .font(.body)
                        BulletPoint("Contact us through the App Store app page")
                        BulletPoint("Remember: we only see what you tell us - not your photos!")
                    }
                    
                    // 9. 数据保留
                    Group {
                        SectionTitle("9. Data Retention")
                        BulletPoint("Photos: Stored until you delete them or uninstall the app")
                        BulletPoint("Settings: Stored until you reset or uninstall")
                        BulletPoint("Subscription: Managed by Apple, not us")
                    }
                    
                    // 10. 国际用户
                    Group {
                        SectionTitle("10. Global Use")
                        Text("This app works the same everywhere: offline-only, local storage, no data collection.")
                            .font(.body)
                    }
                    
                    // 结尾
                    Divider()
                        .padding(.vertical, 16)
                    
                    Text("Bottom line: This is a simple, offline photo organizer. Your photos stay on your device. We can't access them even if we wanted to.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.bottom, 32)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Helper Views
struct SectionTitle: View {
    let title: String
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

struct SubSectionTitle: View {
    let title: String
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct BulletPoint: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    PrivacyPolicyView()
} 