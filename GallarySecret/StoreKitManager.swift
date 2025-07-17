import Foundation
import StoreKit
import Network

@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var subscriptionStatus: SubscriptionStatus = .none
    @Published var isRestoringPurchases = false
    @Published var restoreError: String? = nil
    @Published var restoreSuccess = false
    @Published var isAppleIDSignedIn = false
    
    private let productIDs = [
        "com.mk.gallarysecret.week",
        "com.mk.gallarysecret.monthly", 
        "com.mk.gallarysecret.yearly"
    ]
    
    private var updateListenerTask: Task<Void, Error>? = nil
    private var networkMonitor: NWPathMonitor?
    private var networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // 修复：添加状态缓存机制，避免频繁的权益检查
    private var lastEntitlementCheck: Date = Date(timeIntervalSince1970: 0)
    private let entitlementCheckInterval: TimeInterval = 300 // 5分钟检查一次
    
    // 优化：改进启动逻辑，避免频繁的自动恢复
    private var hasPerformedInitialCheck = false
    private var isFirstLaunch: Bool {
        return !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }
    

    
    private init() {
        updateListenerTask = listenForTransactions()
        setupNetworkMonitoring()
        checkAppleIDStatus()
        
        // 初始化时从UserDefaults读取会员状态，避免启动时会员状态为false
        let savedMemberStatus = UserDefaults.standard.bool(forKey: "isMember")
        if savedMemberStatus {
            print("StoreKit: Read membership status from UserDefaults: \(savedMemberStatus)")
        }
        
        // 标记已经启动过
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
    
    deinit {
        updateListenerTask?.cancel()
        networkMonitor?.cancel()
    }
    
    // 检查Apple ID登录状态
    private func checkAppleIDStatus() {
        // 在StoreKit 2中，我们通过检查是否能够进行支付来判断Apple ID状态
        let canMakePayments = SKPaymentQueue.canMakePayments()
        isAppleIDSignedIn = canMakePayments
        print("StoreKit: Apple ID login status: \(canMakePayments)")
    }
    
    // 设置网络监控
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                print("StoreKit: 网络连接已恢复")
                // 网络恢复时，只进行静默检查，不自动恢复
                Task { @MainActor in
                    if let self = self {
                        await self.silentEntitlementCheck()
                    }
                }
            } else {
                print("StoreKit: 网络连接已断开")
            }
        }
        networkMonitor?.start(queue: networkQueue)
    }
    
    // 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    print("StoreKit: 收到交易更新 - 产品ID: \(transaction.productID)")
                    // 交易更新时立即强制更新状态
                    await self.forceUpdatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    print("StoreKit: 交易验证失败: \(error)")
                }
            }
        }
    }
    
    // 验证交易
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    // 加载产品
    func loadProducts() async {
        isLoading = true
        print("StoreKit: 开始加载产品...")
        print("StoreKit: 产品ID列表: \(productIDs)")
        
        do {
            products = try await Product.products(for: productIDs)
            print("StoreKit: 成功加载 \(products.count) 个产品")
            
            if products.isEmpty {
                print("StoreKit: 警告 - 没有找到任何产品！")
                print("StoreKit: 请检查Bundle ID是否与产品ID前缀匹配")
            } else {
                for product in products {
                    print("StoreKit: 产品详情 - ID: \(product.id)")
                    print("  - 名称: \(product.displayName)")
                    print("  - 价格: \(product.displayPrice)")
                    print("  - 类型: \(product.type)")
                    if product.type == .autoRenewable {
                        let unitDescription = getSubscriptionPeriodDescription(product.subscription?.subscriptionPeriod)
                        print("  - 订阅周期: \(unitDescription)")
                    }
                }
            }
            
            // 加载产品后，进行初始权益检查（不自动恢复）
            if !hasPerformedInitialCheck {
                hasPerformedInitialCheck = true
                await performInitialEntitlementCheck()
            } else {
                await updatePurchasedProducts()
            }
        } catch {
            print("StoreKit: 加载产品失败: \(error)")
            print("StoreKit: 错误详情: \(error.localizedDescription)")
            
            // 提供更详细的错误信息
            if let storeKitError = error as? StoreKitError {
                print("StoreKit: StoreKitError - \(storeKitError)")
            }
            

        }
        
        isLoading = false
    }
    
    // 初始权益检查（启动时执行一次）
    private func performInitialEntitlementCheck() async {
        print("StoreKit: 执行初始权益检查...")
        
        // 检查网络连接
        guard await isNetworkAvailable() else {
            print("StoreKit: 网络不可用，跳过初始权益检查")
            return
        }
        
        // 检查Apple ID登录状态
        checkAppleIDStatus()
        
        // 仅进行静默的权益检查，不主动恢复
        await silentEntitlementCheck()
        
        print("StoreKit: 初始权益检查完成")
    }
    
    // 静默权益检查（不触发恢复购买）
    private func silentEntitlementCheck() async {
        print("StoreKit: 执行静默权益检查...")
        
        // 直接检查当前权益，不调用AppStore.sync()
        await updatePurchasedProducts()
        
        print("StoreKit: 静默权益检查完成，会员状态: \(isMember)")
    }
    
    // 购买产品
    func purchase(_ product: Product) async throws -> Transaction? {
        print("StoreKit: 开始购买产品: \(product.id)")
        
        // 检查Apple ID登录状态
        guard isAppleIDSignedIn else {
            throw StoreError.appleIDNotSignedIn
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            print("StoreKit: 购买成功，开始验证...")
            let transaction = try checkVerified(verification)
            print("StoreKit: 验证成功，产品ID: \(transaction.productID)")
            // 购买成功后立即强制更新状态，不受频率限制
            await forceUpdatePurchasedProducts()
            await transaction.finish()
            print("StoreKit: 交易完成")
            return transaction
        case .userCancelled:
            print("StoreKit: 用户取消购买")
            return nil
        case .pending:
            print("StoreKit: 购买待处理")
            return nil
        default:
            print("StoreKit: 购买失败，未知错误")
            return nil
        }
    }
    
    // 更新已购买的产品
    func updatePurchasedProducts() async {
        // 修复：添加频率限制，避免频繁检查权益导致界面问题
        let now = Date()
        if now.timeIntervalSince(lastEntitlementCheck) < entitlementCheckInterval {
            print("StoreKit: 权益检查过于频繁，跳过本次检查")
            return
        }
        lastEntitlementCheck = now
        
        var purchasedProducts: Set<String> = []
        var hasActiveSubscription = false
        
        print("StoreKit: 开始检查当前权益...")
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                print("StoreKit: 检查权益 - 产品ID: \(transaction.productID), 类型: \(transaction.productType)")
                
                switch transaction.productType {
                case .nonConsumable:
                    purchasedProducts.insert(transaction.productID)
                    print("StoreKit: 非消耗品权益: \(transaction.productID)")
                case .autoRenewable:
                    if let expirationDate = transaction.expirationDate {
                        if expirationDate > Date() {
                            purchasedProducts.insert(transaction.productID)
                            hasActiveSubscription = true
                            print("StoreKit: 有效订阅: \(transaction.productID), 到期时间: \(expirationDate)")
                        } else {
                            print("StoreKit: 过期订阅: \(transaction.productID), 到期时间: \(expirationDate)")
                        }
                    } else {
                        purchasedProducts.insert(transaction.productID)
                        hasActiveSubscription = true
                        print("StoreKit: 永久订阅: \(transaction.productID)")
                    }
                default:
                    print("StoreKit: 其他类型产品: \(transaction.productID)")
                    break
                }
            } catch {
                print("StoreKit: 验证交易失败: \(error)")
            }
        }
        
        purchasedProductIDs = purchasedProducts
        
        // 更新订阅状态
        if hasActiveSubscription {
            subscriptionStatus = .active
        } else if !purchasedProducts.isEmpty {
            subscriptionStatus = .expired
        } else {
            subscriptionStatus = .none
        }
        
        // 更新会员状态
        let isMember = !purchasedProductIDs.isEmpty
        UserDefaults.standard.set(isMember, forKey: "isMember")
        
        print("StoreKit: 权益检查完成 - 会员状态: \(isMember), 订阅状态: \(subscriptionStatus)")
        
        // 发送通知告知界面会员状态已更新
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .membershipStatusDidChange, object: nil)
        }
    }
    
    // 手动恢复购买（用户触发）
    func restorePurchases() async {
        print("StoreKit: 开始手动恢复购买...")
        isRestoringPurchases = true
        restoreError = nil
        restoreSuccess = false
        
        // 检查Apple ID登录状态
        guard isAppleIDSignedIn else {
            restoreError = "请先登录您的Apple ID账户\n\n前往\"设置\" > \"媒体与购买项目\"登录后重试"
            isRestoringPurchases = false
            return
        }
        
        // 检查网络连接
        guard await isNetworkAvailable() else {
            restoreError = "网络连接不可用，请检查网络设置后重试"
            isRestoringPurchases = false
            return
        }
        
        do {
            try await AppStore.sync()
            print("StoreKit: 手动恢复购买 - App Store 同步完成")
            
            // 恢复购买后立即强制更新状态    
            await forceUpdatePurchasedProducts()
            
            // 检查是否成功恢复了购买
            if isMember {
                restoreSuccess = true
                print("StoreKit: 成功恢复购买，用户现在是会员")
            } else {
                restoreError = "未找到可恢复的购买记录\n\n如果您之前购买过会员，请确保使用相同的Apple ID登录"
                print("StoreKit: 未找到可恢复的购买记录")
            }
        } catch {
            print("StoreKit: 手动恢复购买失败: \(error)")
            restoreError = "恢复购买失败: \(error.localizedDescription)"
        }
        
        isRestoringPurchases = false
    }
    

    
    // 重试恢复购买
    func retryRestorePurchases() async {
        print("StoreKit: 重试恢复购买...")
        
        // 等待一段时间再重试
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
        
        await restorePurchases()
    }
    
    // 检查是否是会员
    var isMember: Bool {
        !purchasedProductIDs.isEmpty
    }
    
    // 检查网络可用性
    private func isNetworkAvailable() async -> Bool {
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            let queue = DispatchQueue(label: "NetworkCheck")
            monitor.start(queue: queue)
        }
    }
    
    // 修复：添加强制更新方法，用于特定场景下的立即更新
    func forceUpdatePurchasedProducts() async {
        print("StoreKit: 强制更新权益状态...")
        lastEntitlementCheck = Date(timeIntervalSince1970: 0) // 重置时间戳
        await updatePurchasedProducts()
    }
    
    // 获取订阅状态描述
    var subscriptionStatusDescription: String {
        switch subscriptionStatus {
        case .none:
            return "未订阅"
        case .active:
            return "订阅中"
        case .expired:
            return "订阅已过期"
        }
    }
    
    // 获取订阅周期描述
    private func getSubscriptionPeriodDescription(_ subscriptionPeriod: Product.SubscriptionPeriod?) -> String {
        guard let period = subscriptionPeriod else {
            return "未知"
        }
        
        let valueText = period.value == 1 ? "" : "\(period.value)"
        
        switch period.unit {
        case .day:
            return period.value == 1 ? "每日" : "每\(period.value)天"
        case .week:
            return period.value == 1 ? "每周" : "每\(period.value)周"
        case .month:
            return period.value == 1 ? "每月" : "每\(period.value)个月"
        case .year:
            return period.value == 1 ? "每年" : "每\(period.value)年"
        @unknown default:
            return "未知周期"
        }
    }
    

}

enum StoreError: Error {
    case failedVerification
    case networkUnavailable
    case restoreFailed
    case appleIDNotSignedIn
}

extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "购买验证失败"
        case .networkUnavailable:
            return "网络连接不可用"
        case .restoreFailed:
            return "恢复购买失败"
        case .appleIDNotSignedIn:
            return "请先登录您的Apple ID账户"
        }
    }
}

enum SubscriptionStatus {
    case none
    case active
    case expired
}
