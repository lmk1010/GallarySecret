import SwiftUI

struct MainView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AlbumsListView()
                .tabItem {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Albums")
                }
                .tag(0)
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(1)
        }
        .accentColor(.blue)
        .onChange(of: selectedTab) { newValue in
            // 当切换到相册选项卡时发送通知以刷新相册列表
            if newValue == 0 {
                appLog("MainView: Tab changed to Albums. Posting notification to refresh album list.")
                NotificationCenter.default.post(name: .didUpdateAlbumList, object: nil)
            }
        }
    }
}

struct AlbumsListView: View {
    @State private var albums: [Album] = []
    @State private var showingCreateSheet = false
    @State private var showingDeleteAlert = false
    @State private var albumToDelete: Album?
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var storeManager = StoreKitManager.shared
    
    // 新增状态变量用于选择模式
    @State private var isSelectionMode = false
    @State private var selectedAlbumIDs = Set<UUID>()
    @State private var showingMultiDeleteAlert = false
    
    // 移出相册相关状态
    @State private var showingExportSheet = false
    @State private var albumToExport: Album?
    @State private var showingExportAlert = false
    @State private var exportMessage = ""
    
    // 添加一个强制刷新的方法
    private func reloadAlbums() {
        appLog("AlbumsListView: 开始重新加载相册列表")
        // 修复：添加防抖机制，避免频繁重载导致UI异常
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 在后台线程获取数据
            DispatchQueue.global(qos: .userInitiated).async {
                let dbAlbums = DatabaseManager.shared.getAllAlbums()
                appLog("AlbumsListView: 从数据库获取到 \(dbAlbums.count) 个相册")
                
                // 打印每个相册的详细信息（数据库数据）
                for (index, album) in dbAlbums.enumerated() {
                    appLog("AlbumsListView: 数据库数据[\(index)] - ID: \(album.id.uuidString), 名称: \(album.name), 照片数量: \(album.count)")
                }
                
                // 在主线程更新 UI
                DispatchQueue.main.async {
                    // 直接使用数据库返回的数组，不做任何转换
                    self.albums = dbAlbums
                    
                    // 打印赋值后的数据
                    appLog("AlbumsListView: UI更新后的相册数量: \(self.albums.count)")
                    for (index, album) in self.albums.enumerated() {
                        appLog("AlbumsListView: UI数据[\(index)] - ID: \(album.id.uuidString), 名称: \(album.name), 照片数量: \(album.count)")
                    }
                    
                    // 添加详细日志
                    appLog("AlbumsListView: 强制刷新后加载了 \(self.albums.count) 个相册")
                    for album in self.albums {
                        appLog("AlbumsListView: 刷新后 - 相册 '\(album.name)' 包含 \(album.count) 张照片")
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // 创建新相册卡片 (仅在非选择模式下显示)
                    if !isSelectionMode {
                        VStack {
                            Button(action: {
                                showingCreateSheet = true
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(colorScheme == .dark ? 
                                              Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), 
                                                radius: 5, x: 0, y: 2)
                                    
                                    VStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.blue)
                                        
                                        Text("Create New Photo Album")
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    }
                                    .padding()
                                }
                                .frame(height: 150)
                                .padding(.horizontal)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top)
                    }
                    
                    // 相册列表
                    if albums.isEmpty && !isSelectionMode { // 在选择模式下即使为空也显示列表区域
                        VStack(spacing: 20) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No Photo Albums Yet")
                                .font(.headline)
                                .foregroundColor(.gray)
                            
                            Text("Click the '+' button in the top right corner to create a new photo album")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 50)
                    } else {
                                            ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                        albumRow(album: album, index: index) // 传递索引以判断是否被锁定
                    }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(navigationTitle) // 动态标题
            .navigationBarItems(leading: leadingNavigationButton, trailing: trailingNavigationButtons) // 动态按钮
            .sheet(isPresented: $showingCreateSheet) {
                CreateAlbumView(onAlbumCreated: { newAlbum in
                    reloadAlbums()
                })
            }
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
            .onAppear {
                // 修复：只在真正需要时重新加载相册列表，避免频繁重载导致UI问题
                // 不要每次onAppear都重载，这会与PhotoGridView的操作产生冲突
                if albums.isEmpty {
                    appLog("AlbumsListView: onAppear - 相册列表为空，执行初始加载")
                    reloadAlbums()
                } else {
                    appLog("AlbumsListView: onAppear - 相册列表不为空(\(albums.count)个)，跳过重载")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didUpdateAlbumList)) { _ in
                appLog("AlbumsListView: Received didUpdateAlbumList notification. Reloading albums.")
                // 修复：添加延迟，避免在照片导入过程中立即重载造成冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appLog("AlbumsListView: 延迟处理通知，开始重新加载相册列表")
                    self.reloadAlbums()
                }
            }
            .alert(isPresented: $showingDeleteAlert) { // Single delete confirmation
                Alert(
                                title: Text("Delete Photo Album"),
            message: Text("Are you sure you want to delete photo album \"\(albumToDelete?.name ?? "")\"? This will also delete all photos in the album and cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let album = albumToDelete {
                            performDelete(album)
                        }
                    },
                    secondaryButton: .cancel(Text("Cancel")) {
                         albumToDelete = nil // Clean up
                    }
                )
            }
                    .alert("Delete Selected Photo Albums?", isPresented: $showingMultiDeleteAlert) { // Batch delete confirmation
            Button("Delete", role: .destructive) {
                deleteSelectedAlbums()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the selected \(selectedAlbumIDs.count) photo albums? This will also delete all photos in the albums and cannot be undone.")
        }
            .actionSheet(isPresented: $showingExportSheet) {
                ActionSheet(
                    title: Text("Premium Photo Album"),
                    message: Text("This photo album requires premium membership to view. You can export photos to system album or renew membership to continue using."),
                    buttons: [
                        .default(Text("Export to System Album")) {
                            if let album = albumToExport {
                                exportAlbumToPhotos(album)
                            }
                        },
                        .default(Text("Renew Membership")) {
                            // Navigate to membership purchase page
                            // Add navigation logic here
                        },
                        .cancel(Text("Cancel")) {
                            albumToExport = nil
                        }
                    ]
                )
            }
            .alert("Export Result", isPresented: $showingExportAlert) {
                if exportMessage.contains("Successfully exported") {
                    Button("Confirm Removal") {
                        if let album = albumToExport {
                            removeExportedAlbum(album)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        albumToExport = nil
                    }
                } else {
                    Button("OK", role: .cancel) {
                        albumToExport = nil
                    }
                }
            } message: {
                Text(exportMessage)
            }
            .toolbar { // 底部多选删除工具栏
                 ToolbarItemGroup(placement: .bottomBar) {
                     if isSelectionMode {
                         Spacer()
                         Button("Delete (\(selectedAlbumIDs.count))") {
                             if !selectedAlbumIDs.isEmpty {
                                  showingMultiDeleteAlert = true
                             }
                         }
                         .disabled(selectedAlbumIDs.isEmpty)
                         .foregroundColor(selectedAlbumIDs.isEmpty ? .gray : .red)
                     }
                 }
             }
        }
    }
    
    // MARK: - Subviews
    
    // 重构的相册行视图
    @ViewBuilder
    private func albumRow(album: Album, index: Int) -> some View {
        HStack {
            // 选择模式下的勾选框
            if isSelectionMode {
                Image(systemName: selectedAlbumIDs.contains(album.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedAlbumIDs.contains(album.id) ? .blue : .gray)
                    .font(.title2)
                    .padding(.leading)
                    .onTapGesture { // 点击勾选框也可选择
                        toggleSelection(for: album)
                    }
            }
            
            // AlbumCard 或 NavigationLink
            Group {
                 if isSelectionMode {
                     AlbumCard(album: album, isLocked: isAlbumLocked(index: index))
                         .onTapGesture {
                             toggleSelection(for: album)
                         }
                 } else {
                     if isAlbumLocked(index: index) {
                         // 锁定的相册不能进入，只能进行移出操作
                         AlbumCard(album: album, isLocked: true)
                             .onTapGesture {
                                 showExportOptions(for: album)
                             }
                     } else {
                         // 正常相册可以进入查看
                         NavigationLink(destination: {
                             // 在创建PhotoGridView前打印相册信息
                             let _ = appLog("AlbumsListView: NavigationLink创建PhotoGridView - 相册'\(album.name)'包含\(album.count)张照片")
                             return PhotoGridView(album: album)
                         }()) {
                             AlbumCard(album: album, isLocked: false)
                         }
                         .buttonStyle(PlainButtonStyle())
                     }
                 }
            }
            .contentShape(Rectangle()) // 让空白区域也能触发手势
            .onLongPressGesture {
                 if !isSelectionMode {
                     enterSelectionMode(selecting: album)
                 }
            }
            .contextMenu {
                 // 在非选择模式下才显示右键删除
                 if !isSelectionMode {
                     Button(role: .destructive) {
                         deleteAlbumConfirmation(album) // 触发单个删除确认
                     } label: {
                         Label("Delete Photo Album", systemImage: "trash")
                     }
                 }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                 // 允许在任何模式下滑动删除
                 Button(role: .destructive) {
                     deleteAlbumConfirmation(album) // 触发单个删除确认
                 } label: {
                     Label("Delete", systemImage: "trash")
                 }
             }
        }
        // 添加动画
        .animation(.easeInOut(duration: 0.2), value: isSelectionMode)
        .animation(.easeInOut(duration: 0.15), value: selectedAlbumIDs.contains(album.id))
    }
    
    // MARK: - Navigation Bar Items
    
    private var navigationTitle: String {
        isSelectionMode ? "Selected \(selectedAlbumIDs.count) items" : "Private Photo Albums"
    }

    private var leadingNavigationButton: some View {
        Group {
            if isSelectionMode {
                Button("Cancel") {
                    exitSelectionMode()
                }
            } else {
                EmptyView() // 非选择模式下不显示
            }
        }
    }

    private var trailingNavigationButtons: some View {
        Group {
            if isSelectionMode {
                // 选择模式下不显示"+"按钮
                EmptyView()
            } else {
                // 非选择模式下显示 "选择" 和 "+"
                 HStack {
                    Button("Select") {
                        enterSelectionMode()
                    }
                     
                    Button(action: {
                        showingCreateSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                 }
            }
        }
    }
    
    // MARK: - Actions & Logic
    
    // 判断相册是否被锁定
    private func isAlbumLocked(index: Int) -> Bool {
        // 如果是会员，所有相册都不锁定
        if storeManager.isMember {
            return false
        }
        
        // 非会员用户：第2个及以后的相册被锁定
        return index >= 1
    }
    
    // 显示移出选项
    private func showExportOptions(for album: Album) {
        albumToExport = album
        showingExportSheet = true
    }
    
    // 进入选择模式
    private func enterSelectionMode(selecting album: Album? = nil) {
        isSelectionMode = true
        selectedAlbumIDs.removeAll() // 清空之前的选择
        if let albumToSelect = album {
            selectedAlbumIDs.insert(albumToSelect.id) // 选中长按的相册
        }
    }

    // 退出选择模式
    private func exitSelectionMode() {
        isSelectionMode = false
        selectedAlbumIDs.removeAll()
    }

    // 切换相册选中状态
    private func toggleSelection(for album: Album) {
        if selectedAlbumIDs.contains(album.id) {
            selectedAlbumIDs.remove(album.id)
        } else {
            selectedAlbumIDs.insert(album.id)
        }
    }

    // 删除单个相册（触发确认）- 重命名以区分
    private func deleteAlbumConfirmation(_ album: Album) {
        self.albumToDelete = album
        self.showingDeleteAlert = true
    }
    
    // 执行单个删除操作
    private func performDelete(_ album: Album) {
        // 从数据库中删除
        if DatabaseManager.shared.deleteAlbum(withId: album.id) {
            // 更新UI
            if let index = albums.firstIndex(where: { $0.id == album.id }) {
                albums.remove(at: index)
                appLog("Successfully deleted album: \(album.name)")
            }
        } else {
            appLog("Failed to delete album: \(album.name)")
            // 可以考虑添加错误提示
        }
        albumToDelete = nil // 清理
    }
    
    // 删除选中的相册
    private func deleteSelectedAlbums() {
         let idsToDelete = selectedAlbumIDs // 复制一份
         var deletedCount = 0
         appLog("Attempting to delete \(idsToDelete.count) selected albums.")

         for albumId in idsToDelete {
             if DatabaseManager.shared.deleteAlbum(withId: albumId) {
                 deletedCount += 1
                 appLog("Successfully deleted album with ID: \(albumId)")
             } else {
                 appLog("Failed to delete album with ID: \(albumId)")
                 // 可以考虑给用户一些反馈
             }
         }

         appLog("Finished deleting. Deleted \(deletedCount) out of \(idsToDelete.count) albums.")

         // 移除已删除的相册并退出选择模式
         albums.removeAll { idsToDelete.contains($0.id) }
         exitSelectionMode() // 退出选择模式并清空 selectedAlbumIDs
    }
    
    // 导出相册到系统相册
    private func exportAlbumToPhotos(_ album: Album) {
        appLog("Start exporting album '\(album.name)' to system photos")
        
        Task {
            do {
                // 获取相册中的所有照片
                let photos = PhotoManager.shared.getPhotos(fromAlbum: album.id)
                var exportedCount = 0
                var failedCount = 0
                
                for photo in photos {
                    do {
                        // 获取照片的完整路径
                        guard let photoURL = photo.imagePath else {
                            failedCount += 1
                            appLog("Unable to get photo path: \(photo.fileName)")
                            continue
                        }
                        
                        // 检查文件是否存在
                        if FileManager.default.fileExists(atPath: photoURL.path) {
                            let imageData = try Data(contentsOf: photoURL)
                            if let uiImage = UIImage(data: imageData) {
                                // 保存到系统相册
                                try await PhotoManager.shared.saveImageToPhotos(uiImage)
                                exportedCount += 1
                                appLog("Successfully exported photo: \(photo.fileName)")
                            } else {
                                failedCount += 1
                                appLog("Unable to create UIImage: \(photo.fileName)")
                            }
                        } else {
                            failedCount += 1
                            appLog("Photo file does not exist: \(photoURL.path)")
                        }
                    } catch {
                        failedCount += 1
                        appLog("Failed to export photo: \(photo.fileName), error: \(error)")
                    }
                }
                
                // 导出完成后的处理
                DispatchQueue.main.async {
                    if exportedCount > 0 {
                        self.exportMessage = "Successfully exported \(exportedCount) photos to system album"
                        if failedCount > 0 {
                            self.exportMessage += ", \(failedCount) photos failed to export"
                        }
                        self.exportMessage += ". The album will be removed from the app."
                        
                        // 显示成功提示，询问是否删除相册
                        self.showingExportAlert = true
                    } else {
                        self.exportMessage = "Failed to export album, please try again later."
                        self.showingExportAlert = true
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.exportMessage = "An error occurred while exporting the album: \(error.localizedDescription)"
                    self.showingExportAlert = true
                }
            }
        }
    }
    
    // 完成导出后删除相册
    private func removeExportedAlbum(_ album: Album) {
        // 删除相册及其所有照片
        if DatabaseManager.shared.deleteAlbum(withId: album.id) {
            // 更新UI
            if let index = albums.firstIndex(where: { $0.id == album.id }) {
                albums.remove(at: index)
                appLog("Deleted exported album: \(album.name)")
            }
        }
        albumToExport = nil
    }
}

struct Album: Identifiable, Equatable {
    let id: UUID
    let name: String
    let coverImage: String
    var count: Int
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, coverImage: String, count: Int, createdAt: Date) {
        self.id = id
        self.name = name
        self.coverImage = coverImage
        self.count = count
        self.createdAt = createdAt
    }
    
    // Implement Equatable
    static func == (lhs: Album, rhs: Album) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.coverImage == rhs.coverImage &&
               lhs.count == rhs.count &&
               lhs.createdAt == rhs.createdAt
    }
}

struct AlbumCard: View {
    let album: Album
    let isLocked: Bool
    @Environment(\.colorScheme) var colorScheme
    
    init(album: Album, isLocked: Bool = false) {
        self.album = album
        self.isLocked = isLocked
        appLog("AlbumCard: 创建相册卡片 '\(album.name)'，显示照片数量: \(album.count)，锁定状态: \(isLocked)")
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(colorScheme == .dark ? 
                      Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), 
                        radius: 8, x: 0, y: 2)
                .opacity(isLocked ? 0.7 : 1.0)
            
            // 锁定遮罩层
            if isLocked {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.3))
            }
            
            HStack {
                // 封面图
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? 
                              Color(UIColor.systemGray5) : Color.gray.opacity(0.2))
                    
                    if album.coverImage.isEmpty {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 30))
                            .foregroundColor(colorScheme == .dark ? .gray : .gray)
                    } else {
                        Image(album.coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(width: 80, height: 80)
                
                // 相册信息
                VStack(alignment: .leading, spacing: 8) {
                    Text(album.name)
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    HStack {
                        Text("\(album.count) photos")
                            .id("count-\(album.id)-\(album.count)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(dateFormatter.string(from: album.createdAt))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.leading, 15)
                
                Spacer()
                
                if isLocked {
                    VStack(spacing: 2) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.yellow)
                        Text("Premium")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    .padding(.trailing, 8)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .padding(.trailing, 5)
                }
            }
            .padding()
        }
        .padding(.horizontal)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
}

struct CreateAlbumView: View {
    @Environment(\.presentationMode) var presentationMode
    var onAlbumCreated: (Album) -> Void
    @State private var albumName = ""
    @State private var showMembershipAlert = false
    @ObservedObject private var storeManager = StoreKitManager.shared
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Album Information")) {
                    TextField("Album Name", text: $albumName)
                }
            }
            .navigationTitle("Create New Photo Album")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Create") {
                    if !albumName.isEmpty {
                        // 如果是会员或者相册数量小于1，允许创建
                        if storeManager.isMember || DatabaseManager.shared.getAllAlbums().count < 1 {
                            let newAlbum = Album(
                                name: albumName,
                                coverImage: "",
                                count: 0,
                                createdAt: Date()
                            )
                            
                            // 保存到数据库
                            if DatabaseManager.shared.saveAlbum(newAlbum) {
                                onAlbumCreated(newAlbum)
                                presentationMode.wrappedValue.dismiss()
                            }
                        } else {
                            // Non-member with existing album, show membership alert
                            showMembershipAlert = true
                        }
                    }
                }
                .disabled(albumName.isEmpty)
            )
            .alert(isPresented: $showMembershipAlert) {
                Alert(
                    title: Text("Membership Limitation"),
                    message: Text("Free users can only create one album. Upgrade to premium to create unlimited albums."),
                    primaryButton: .default(Text("Upgrade to Premium")) {
                        // Navigate to membership purchase page
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
            .onAppear {
                // Update membership status on initialization
                Task {
                    await storeManager.forceUpdatePurchasedProducts()
                }
            }
        }
    }
}

struct ProfileView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showingPasswordSettings = false
    @State private var showingMembership = false
    @State private var showingPrivacyPolicy = false
    @State private var storageSize: String = "Calculating..."
    @ObservedObject private var storeManager = StoreKitManager.shared
    @State private var showRestoreAlert = false
    @State private var restoreAlertMessage = ""
    @State private var restoreAlertTitle = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // User avatar
                Circle()
                    .fill(colorScheme == .dark ? 
                          Color(UIColor.systemGray5) : Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: storeManager.isMember ? "crown.fill" : "person.fill")
                            .font(.system(size: 50))
                            .foregroundColor(storeManager.isMember ? .yellow : 
                                             (colorScheme == .dark ? Color.gray.opacity(0.8) : .gray))
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), 
                            radius: 5, x: 0, y: 2)
                    .padding(.top, 30)
                
                Text(storeManager.isMember ? "Premium User" : "Free User")
                    .font(.title)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.top, 8)
                
                // Options list
                List {
                    Section {
                        HStack {
                            Label("Photo Storage", systemImage: "photo.on.rectangle")
                            Spacer()
                            Text(storageSize)
                                .foregroundColor(.gray)
                        }
                        
                        Button(action: {
                            showingPasswordSettings = true
                        }) {
                            HStack {
                                Label("Calculator Password", systemImage: "lock.shield")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Button(action: {
                            showingMembership = true
                        }) {
                            HStack {
                                Label("Premium Service", systemImage: "crown.fill")
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
                    
                    Section {
                        Button(action: {
                            showingPrivacyPolicy = true
                        }) {
                            HStack {
                                Label("Privacy Policy", systemImage: "doc.text")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .foregroundColor(.primary)
                        
                        HStack {
                            Label("Version", systemImage: "info.circle")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Profile")
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
            .sheet(isPresented: $showingPasswordSettings) {
                PasswordSettingsView()
            }
            .sheet(isPresented: $showingMembership) {
                MembershipView()
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .alert(restoreAlertTitle, isPresented: $showRestoreAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(restoreAlertMessage)
            }
            .onAppear {
                calculateStorageSize()
                // Update membership status
                Task {
                    await storeManager.forceUpdatePurchasedProducts()
                }
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
        print("ProfileView: Starting restore purchases...")
        await storeManager.restorePurchases()
    }
    
    private func calculateStorageSize() {
        let albums = DatabaseManager.shared.getAllAlbums()
        let totalPhotos = albums.reduce(0) { $0 + $1.count }
        storageSize = "\(totalPhotos) photos"
    }
}

// Extend FileManager to calculate directory size
extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var totalSize: UInt64 = 0
        
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles], errorHandler: { (_, error) -> Bool in
            print("Error enumerating directory: \(error)")
            return true
        })!
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            if resourceValues.isRegularFile ?? false {
                totalSize += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }
        
        return totalSize
    }
}

#Preview {
    MainView()
} 
