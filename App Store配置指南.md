# App Store 上架配置指南

## 📱 StoreKit 线上配置

### 1. App Store Connect 配置

#### 1.1 创建应用内购买项目

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)
2. 选择你的应用
3. 进入 **功能** > **应用内购买项目**
4. 点击 **+** 创建新的应用内购买项目

#### 1.2 配置订阅产品

为每个订阅计划创建产品：

**周会员订阅**
- 产品ID：`com.mk.gallarysecret.week`
- 类型：自动续订订阅
- 订阅组：创建新组或选择现有组
- 订阅时长：1周
- 价格：根据你的定价策略设置

**月会员订阅**
- 产品ID：`com.mk.gallarysecret.monthly`
- 类型：自动续订订阅
- 订阅组：与周会员相同
- 订阅时长：1月
- 价格：根据你的定价策略设置

**年会员订阅**
- 产品ID：`com.mk.gallarysecret.yearly`
- 类型：自动续订订阅
- 订阅组：与周会员相同
- 订阅时长：1年
- 价格：根据你的定价策略设置

#### 1.3 配置本地化信息

为每个产品添加本地化描述：

**中文 (简体)**
- 显示名称：根据产品类型（如：周会员、月会员、年会员）
- 描述：详细描述会员权益

**英文**
- 显示名称：Weekly/Monthly/Yearly Membership
- 描述：Premium features description

### 2. Xcode 项目配置

#### 2.1 更新 Bundle ID
确保你的 Bundle ID 与 App Store Connect 中的应用 Bundle ID 完全匹配

#### 2.2 配置 Capabilities
1. 在 Xcode 中选择项目
2. 选择 **Signing & Capabilities**
3. 添加 **In-App Purchase** capability

#### 2.3 移除 StoreKit Configuration
1. 在 Xcode 中，选择 **Product** > **Scheme** > **Edit Scheme**
2. 选择 **Run** > **Options**
3. 在 **StoreKit Configuration** 部分，选择 **None**
4. 这样应用将使用真实的 App Store 环境

### 3. 测试配置

#### 3.1 创建沙盒测试账户
1. 在 App Store Connect 中
2. 进入 **用户和访问** > **沙盒测试员**
3. 创建测试账户，用于测试应用内购买

#### 3.2 测试流程
1. 在真机上安装应用（不能在模拟器中测试真实的 StoreKit）
2. 登出当前 Apple ID
3. 在应用中尝试购买
4. 使用沙盒测试账户登录
5. 完成购买流程测试

### 4. 提交审核前检查清单

#### 4.1 功能检查
- [ ] 所有订阅产品正确显示价格
- [ ] 购买流程正常工作
- [ ] 恢复购买功能正常
- [ ] 会员权益正确生效
- [ ] 订阅到期后权益正确移除

#### 4.2 代码检查
- [ ] 移除所有调试和测试代码
- [ ] 移除 Product.storekit 文件
- [ ] Scheme 中不使用 StoreKit Configuration
- [ ] 产品ID与App Store Connect配置完全匹配

#### 4.3 用户体验检查
- [ ] 购买失败时有适当的错误提示
- [ ] Apple ID未登录时有友好提示
- [ ] 网络断开时有适当处理
- [ ] 界面符合Apple设计规范

### 5. 常见问题解决

#### 5.1 产品加载失败
- 检查 Bundle ID 是否与 App Store Connect 匹配
- 确认产品ID拼写完全正确
- 确认产品状态为"准备提交"或"等待审核"

#### 5.2 购买失败
- 确认使用真机测试，不是模拟器
- 检查是否使用沙盒测试账户
- 确认产品已在 App Store Connect 中配置

#### 5.3 恢复购买不工作
- 确认订阅组配置正确
- 检查Transaction验证逻辑
- 确认网络连接正常

### 6. 上架后监控

#### 6.1 关键指标
- 订阅转化率
- 订阅留存率
- 收入数据
- 崩溃率

#### 6.2 用户反馈
- 监控App Store评论
- 关注购买相关问题
- 及时回应用户反馈

## 🔧 技术细节

### 产品ID配置
应用中配置的产品ID：
```swift
private let productIDs = [
    "com.mk.gallarysecret.week",
    "com.mk.gallarysecret.monthly", 
    "com.mk.gallarysecret.yearly"
]
```

这些ID必须与App Store Connect中的产品ID完全匹配。

### 订阅组重要性
所有订阅产品应该在同一个订阅组中，这样：
- 用户同时只能有一个活跃订阅
- 用户可以在不同订阅级别间升级/降级
- 支持恢复购买功能

## 📋 提交审核注意事项

1. **隐私政策**：确保应用有完整的隐私政策
2. **用户协议**：添加服务条款和用户协议
3. **订阅信息**：在购买页面清楚显示订阅条款
4. **取消订阅**：提供取消订阅的说明
5. **免费试用**：如果提供试用，确保条款清晰

记住：App Store 审核团队会特别关注应用内购买的实现，确保遵循所有相关指南。 