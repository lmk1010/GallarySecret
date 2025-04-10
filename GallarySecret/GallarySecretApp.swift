//
//  GallarySecretApp.swift
//  GallarySecret
//
//  Created by 刘明康 on 2025/4/10.
//

import SwiftUI
import OSLog

// 全局日志函数
func appLog(_ message: String) {
    #if DEBUG
    print("[GallarySecret] \(message)")
    os_log("%{public}@", log: OSLog(subsystem: "com.mk.GallarySecret", category: "App"), type: .debug, message)
    #endif
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
            CalculatorView()
        }
    }
}
