import SwiftUI
import StoreKit

struct MembershipView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var storeManager = StoreKitManager.shared
    @State private var selectedProduct: Product?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isPurchasing = false
    @State private var animateGradient = false
    @State private var showRestoreAlert = false
    @State private var restoreAlertMessage = ""
    @State private var restoreAlertTitle = ""
    @State private var showAppleIDAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                MembershipBackgroundView(animateGradient: animateGradient)
                
                ScrollView {
                    VStack(spacing: 40) {
                        MembershipHeaderView(
                            isMember: storeManager.isMember,
                            subscriptionStatus: storeManager.subscriptionStatusDescription
                        )
                        
                        // 智能恢复建议（只在需要时显示）
                        if !storeManager.isMember && !storeManager.isAppleIDSignedIn {
                            MembershipRestoreSuggestionView(
                                suggestion: "Apple ID not signed in detected. If you have purchased membership before, please sign in to Apple ID first and then click \"Restore Purchases\"",
                                onRestore: restorePurchases
                            )
                        }
                        
                        MembershipFeaturesView()
                        
                        MembershipPlansView(
                            products: storeManager.products,
                            selectedProduct: selectedProduct,
                            purchasedProductIDs: storeManager.purchasedProductIDs,
                            isLoading: storeManager.isLoading,
                            isMember: storeManager.isMember,
                            isPurchasing: isPurchasing,
                            isRestoringPurchases: storeManager.isRestoringPurchases,
                            isAppleIDSignedIn: storeManager.isAppleIDSignedIn,
                            onProductSelect: { selectedProduct = $0 },
                            onPurchase: purchaseSelectedProduct,
                            onRestore: restorePurchases
                        )
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .overlay(
                MembershipNavigationBar(onDismiss: {
                    presentationMode.wrappedValue.dismiss()
                }),
                alignment: .top
            )
            .onAppear {
                animateGradient = true
                Task {
                    await storeManager.loadProducts()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .membershipStatusDidChange)) { _ in
                if storeManager.isMember {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
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
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func purchaseSelectedProduct() {
        guard let product = selectedProduct else {
            errorMessage = "Please select a plan"
            showError = true
            return
        }
        
        // 检查Apple ID登录状态
        guard storeManager.isAppleIDSignedIn else {
            errorMessage = "Please sign in to your Apple ID account first\n\nGo to \"Settings\" > \"Media & Purchases\" to sign in and try again"
            showError = true
            return
        }
        
        Task {
            isPurchasing = true
            do {
                let transaction = try await storeManager.purchase(product)
                if transaction != nil {
                    presentationMode.wrappedValue.dismiss()
                }
                                } catch StoreError.appleIDNotSignedIn {
                        errorMessage = "Please sign in to your Apple ID account first\n\nGo to \"Settings\" > \"Media & Purchases\" to sign in and try again"
                        showError = true
            } catch {
                errorMessage = "Purchase failed: \(error.localizedDescription)"
                showError = true
            }
            isPurchasing = false
        }
    }
    
    private func restorePurchases() {
        Task {
            await storeManager.restorePurchases()
        }
    }
    
    private func getDuration(for product: Product) -> String {
        switch product.id {
        case "com.mk.gallarysecret.week":
            return "Weekly"
        case "com.mk.gallarysecret.monthly":
            return "Monthly"
        case "com.mk.gallarysecret.yearly":
            return "Yearly"
        default:
            return ""
        }
    }
    
    private func isPopular(product: Product) -> Bool {
        return product.id == "com.mk.gallarysecret.yearly"
    }
    
    private func getSavings(for product: Product) -> String? {
        switch product.id {
        case "com.mk.gallarysecret.yearly":
            return "Save 60%"
        case "com.mk.gallarysecret.monthly":
            return "Most Popular"
        default:
            return nil
        }
    }
}

struct MembershipBackgroundView: View {
    let animateGradient: Bool
    
    var body: some View {
        Color.black.opacity(0.93)
            .ignoresSafeArea()
    }
}

struct MembershipHeaderView: View {
    let isMember: Bool
    let subscriptionStatus: String
    
    var body: some View {
        VStack(spacing: 24) {
            MembershipCrownIcon(isMember: isMember)
            
            VStack(spacing: 12) {
                Text(isMember ? "Premium Member" : "Upgrade to Premium")
                    .font(.system(size: 32, weight: .light, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                if isMember {
                    Text(subscriptionStatus)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(20)
                } else {
                    Text("Unlock unlimited photo storage & premium features")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .padding(.top, 60)
    }
}

struct MembershipCrownIcon: View {
    let isMember: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: isMember ? 
                            [Color.yellow.opacity(0.4), Color.clear] :
                            [Color.white.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
            
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 100, height: 100)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            Image(systemName: isMember ? "crown.fill" : "crown")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: isMember ? 
                            [Color.yellow, Color.orange] :
                            [Color.white, Color.white.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(isMember ? 1.1 : 1.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isMember)
        }
    }
}

struct MembershipFeaturesView: View {
    var body: some View {
        VStack(spacing: 20) {
            PremiumFeatureCard(
                icon: "infinity",
                title: "Unlimited Photo Storage",
                description: "Store unlimited photos"
            )
            
            PremiumFeatureCard(
                icon: "folder.badge.plus",
                title: "Unlimited Photo Albums",
                description: "Create unlimited private photo albums"
            )
            
            PremiumFeatureCard(
                icon: "key.fill",
                title: "Custom Password",
                description: "Set personalized unlock password"
            )
        }
        .padding(.horizontal, 20)
    }
}

struct MembershipPlansView: View {
    let products: [Product]
    let selectedProduct: Product?
    let purchasedProductIDs: Set<String>
    let isLoading: Bool
    let isMember: Bool
    let isPurchasing: Bool
    let isRestoringPurchases: Bool
    let isAppleIDSignedIn: Bool
    let onProductSelect: (Product) -> Void
    let onPurchase: () -> Void
    let onRestore: () -> Void
    
    var body: some View {
        if !products.isEmpty {
            VStack(spacing: 16) {
                ForEach(products, id: \.id) { product in
                    PremiumPlanCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        isPurchased: purchasedProductIDs.contains(product.id),
                        isPurchasing: isPurchasing,
                        onSelect: { 
                            onProductSelect(product)
                            if !purchasedProductIDs.contains(product.id) {
                                onPurchase()
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            if !isMember {
                VStack(spacing: 16) {
                    Button(action: onRestore) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                            Text("Restore Purchase")
                                .font(.system(size: 16, weight: .medium))
                            
                            if isRestoringPurchases {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                        }
                        .foregroundColor(isAppleIDSignedIn ? .white.opacity(0.8) : .white.opacity(0.5))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(isAppleIDSignedIn ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(Color.white.opacity(isAppleIDSignedIn ? 0.3 : 0.15), lineWidth: 0.5)
                                )
                        )
                    }
                    .disabled(isPurchasing || isRestoringPurchases || !isAppleIDSignedIn)
                    
                    Text("If you have purchased membership before, you can restore your purchase through this button")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, 20)
            }
        } else if isLoading {
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
                Text("Loading...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.vertical, 60)
        }
    }
}

struct MembershipNavigationBar: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            Spacer()
        }
    }
}

struct PremiumFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

struct PremiumPlanCard: View {
    let product: Product
    let isSelected: Bool
    let isPurchased: Bool
    let isPurchasing: Bool
    let onSelect: () -> Void
    
    private var duration: String {
        switch product.id {
        case "com.mk.gallarysecret.week":
            return "Weekly"
        case "com.mk.gallarysecret.monthly":
            return "Monthly"
        case "com.mk.gallarysecret.yearly":
            return "Yearly"
        default:
            return ""
        }
    }
    
    private var isPopular: Bool {
        product.id == "com.mk.gallarysecret.yearly"
    }
    
    private var badgeText: String? {
        switch product.id {
        case "com.mk.gallarysecret.yearly":
            return "Best Value"
        case "com.mk.gallarysecret.monthly":
            return "Most Popular"
        default:
            return nil
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                PlanCardContent(
                    duration: duration,
                    price: product.displayPrice,
                    isSelected: isSelected,
                    isPurchased: isPurchased,
                    isPurchasing: isPurchasing && isSelected
                )
                
                if let badgeText = badgeText, !isPurchased {
                    PlanBadge(text: badgeText, isPopular: isPopular)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPurchased || isPurchasing)
        .scaleEffect(isSelected && isPurchasing ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPurchasing)
    }
}

struct PlanCardContent: View {
    let duration: String
    let price: String
    let isSelected: Bool
    let isPurchased: Bool
    let isPurchasing: Bool
    
    var body: some View {
        HStack {
            PlanCardLeftSide(duration: duration, isPurchasing: isPurchasing && isSelected)
            Spacer()
            PlanCardRightSide(price: price, isPurchased: isPurchased, isPurchasing: isPurchasing && isSelected)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(PlanCardBackground(isSelected: isSelected, isPurchased: isPurchased))
    }
}

struct PlanCardLeftSide: View {
    let duration: String
    let isPurchasing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(duration)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
            
            if isPurchasing {
                Text("Processing...")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("Premium Access")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct PlanCardRightSide: View {
    let price: String
    let isPurchased: Bool
    let isPurchasing: Bool
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isPurchased {
                PurchaseStatusIndicator()
            } else if isPurchasing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                Text(price)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 1)
            }
        }
    }
}

struct PurchaseStatusIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Activated")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.green)
        }
    }
}

struct PlanCardBackground: View {
    let isSelected: Bool
    let isPurchased: Bool
    
    var backgroundView: some View {
        if isPurchased || isSelected {
            return AnyView(Color.white.opacity(0.20))
        } else {
            return AnyView(Color.white.opacity(0.12))
        }
    }
    
    var strokeGradient: AnyShapeStyle {
        if isPurchased {
            return AnyShapeStyle(Color.green.opacity(0.6))
        } else if isSelected {
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else {
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.2), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
    }
    
    var shadowColor: Color {
        if isPurchased {
            return Color.green.opacity(0.3)
        } else if isSelected {
            return Color.white.opacity(0.2)
        } else {
            return Color.black.opacity(0.2)
        }
    }
    
    var shadowRadius: CGFloat {
        isPurchased || isSelected ? 15 : 8
    }
    
    var shadowY: CGFloat {
        isPurchased || isSelected ? 8 : 4
    }
    
    var strokeWidth: CGFloat {
        isPurchased || isSelected ? 2 : 1
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.clear)
            .background(backgroundView)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(strokeGradient, lineWidth: strokeWidth)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }
}

struct PlanBadge: View {
    let text: String
    let isPopular: Bool
    
    var badgeGradient: LinearGradient {
        LinearGradient(
            colors: isPopular ? 
                [Color.orange, Color.red] :
                [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                Text(text)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(badgeGradient)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            Spacer()
        }
        .padding(.top, -6)
        .padding(.trailing, 12)
    }
}

struct MembershipRestoreSuggestionView: View {
    let suggestion: String
    let onRestore: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                
                Text(suggestion)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            
            Button(action: onRestore) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                    Text("Restore Purchase")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

#Preview {
    MembershipView()
}