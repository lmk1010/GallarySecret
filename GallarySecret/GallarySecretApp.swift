//
//  GallarySecretApp.swift
//  GallarySecret
//
//  Created by 刘明康 on 2025/4/10.
//

import SwiftUI
import OSLog
import Network

// 全局日志函数
func appLog(_ message: String) {
    print("[GallarySecret] \(message)")
}

// 全局图片缓存预热
func prewarmImageRendering() {
    appLog("预热图片渲染引擎...")
    
    // 创建临时图像并进行简单渲染以初始化渲染管道
    let image = UIImage(systemName: "photo")!
    
    // 使用UIGraphicsImageRenderer预热图像渲染
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format)
    _ = renderer.image { context in
        image.draw(in: CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    
    // 使用SwiftUI方式预热图像显示
    let _ = Image(uiImage: image)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .frame(width: 100, height: 100)
    
    appLog("图片渲染预热完成")
}

@main
struct GallarySecretApp: App {
    init() {
        appLog("应用启动")
        
        // 执行图片渲染预热
        prewarmImageRendering()
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    // 应用启动时初始化StoreKit并检查购买状态
                    Task {
                        await initializeStoreKit()
                        await setupPasswordManagement()
                    }
                }
        }
    }
    
    private func initializeStoreKit() async {
        appLog("初始化StoreKit...")
        
        // 加载产品（内部已包含智能的初始权益检查）
        await StoreKitManager.shared.loadProducts()
        
        // 检查网络连接状态
        let isConnected = await isNetworkConnected()
        appLog("网络连接状态: \(isConnected)")
        
        // 应用启动时只进行静默检查，不强制恢复购买
        if isConnected {
            appLog("网络可用，StoreKit已完成初始化和权益检查")
        } else {
            appLog("网络不可用，将在网络恢复后自动检查购买状态")
        }
    }
    
    private func setupPasswordManagement() async {
        appLog("设置密码管理...")
        
        // 检查用户是否是会员
        let isMember = StoreKitManager.shared.isMember
        appLog("用户会员状态: \(isMember)")
        
        // 如果不是会员，强制设置默认密码为 1234
        if !isMember {
            let currentPassword = UserDefaults.standard.string(forKey: "computerPassword")
            if currentPassword != "1234" {
                appLog("普通用户检测到非默认密码，重置为默认密码 1234")
                UserDefaults.standard.set("1234", forKey: "computerPassword")
            } else {
                appLog("普通用户使用默认密码 1234")
            }
        } else {
            // 如果是会员，检查是否有自定义密码，如果没有则设置默认密码
            let currentPassword = UserDefaults.standard.string(forKey: "computerPassword")
            if currentPassword == nil {
                appLog("会员用户首次使用，设置默认密码 1234")
                UserDefaults.standard.set("1234", forKey: "computerPassword")
            } else {
                appLog("会员用户使用自定义密码")
            }
        }
        
        // 监听会员状态变化
        NotificationCenter.default.addObserver(
            forName: .membershipStatusDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await self.handleMembershipStatusChange()
            }
        }
    }
    
    private func handleMembershipStatusChange() async {
        appLog("会员状态发生变化")
        
        let isMember = StoreKitManager.shared.isMember
        appLog("新的会员状态: \(isMember)")
        
        // 如果从会员变为普通用户，重置为默认密码
        if !isMember {
            appLog("用户从会员变为普通用户，重置密码为默认密码 1234")
            UserDefaults.standard.set("1234", forKey: "computerPassword")
        }
        // 如果从普通用户变为会员，保持当前密码不变（可能是1234或用户之前设置的密码）
    }
    
    private func isNetworkConnected() async -> Bool {
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
}
