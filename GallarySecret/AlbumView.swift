import SwiftUI

struct MainView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AlbumsListView()
                .tabItem {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("相册")
                }
                .tag(0)
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("我的")
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
    
    // 新增状态变量用于选择模式
    @State private var isSelectionMode = false
    @State private var selectedAlbumIDs = Set<UUID>()
    @State private var showingMultiDeleteAlert = false
    
    // 添加一个强制刷新的方法
    private func reloadAlbums() {
        appLog("AlbumsListView: 开始重新加载相册列表")
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
                                        
                                        Text("创建新相册")
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
                            
                            Text("还没有相册")
                                .font(.headline)
                                .foregroundColor(.gray)
                            
                            Text("点击右上角的"+"按钮创建一个新相册")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 50)
                    } else {
                        ForEach(albums) { album in
                            albumRow(album: album) // 使用重构的行视图
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
                // 每次进入页面时强制从数据库重新加载相册数据
                appLog("AlbumsListView: onAppear 强制刷新相册列表")
                reloadAlbums()
            }
            .onReceive(NotificationCenter.default.publisher(for: .didUpdateAlbumList)) { _ in
                appLog("AlbumsListView: Received didUpdateAlbumList notification. Reloading albums.")
                // 收到通知后重新加载相册数据
                reloadAlbums()
            }
            .alert(isPresented: $showingDeleteAlert) { // 单个删除确认 - 移除外部标题
                Alert(
                    title: Text("删除相册"),
                    message: Text("确定要删除相册\"\(albumToDelete?.name ?? "")\"吗？此操作将同时删除相册内的所有照片，且不可恢复。"),
                    primaryButton: .destructive(Text("删除")) {
                        if let album = albumToDelete {
                            performDelete(album)
                        }
                    },
                    secondaryButton: .cancel(Text("取消")) {
                         albumToDelete = nil // 清理
                    }
                )
            }
            .alert("删除所选相册?", isPresented: $showingMultiDeleteAlert) { // 批量删除确认
                 Button("删除", role: .destructive) {
                     deleteSelectedAlbums()
                 }
                 Button("取消", role: .cancel) {}
             } message: {
                 Text("确定要删除选中的 \(selectedAlbumIDs.count) 个相册吗？此操作将同时删除相册内的所有照片，且不可恢复。")
             }
            .toolbar { // 底部多选删除工具栏
                 ToolbarItemGroup(placement: .bottomBar) {
                     if isSelectionMode {
                         Spacer()
                         Button("删除 (\(selectedAlbumIDs.count))") {
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
    private func albumRow(album: Album) -> some View {
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
                     AlbumCard(album: album)
                         .onTapGesture {
                             toggleSelection(for: album)
                         }
                 } else {
                     NavigationLink(destination: {
                         // 在创建PhotoGridView前打印相册信息
                         let _ = appLog("AlbumsListView: NavigationLink创建PhotoGridView - 相册'\(album.name)'包含\(album.count)张照片")
                         return PhotoGridView(album: album)
                     }()) {
                         AlbumCard(album: album)
                     }
                     .buttonStyle(PlainButtonStyle())
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
                         Label("删除相册", systemImage: "trash")
                     }
                 }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                 // 允许在任何模式下滑动删除
                 Button(role: .destructive) {
                     deleteAlbumConfirmation(album) // 触发单个删除确认
                 } label: {
                     Label("删除", systemImage: "trash")
                 }
             }
        }
        // 添加动画
        .animation(.easeInOut(duration: 0.2), value: isSelectionMode)
        .animation(.easeInOut(duration: 0.15), value: selectedAlbumIDs.contains(album.id))
    }
    
    // MARK: - Navigation Bar Items
    
    private var navigationTitle: String {
        isSelectionMode ? "已选择 \(selectedAlbumIDs.count) 项" : "隐私相册"
    }

    private var leadingNavigationButton: some View {
        Group {
            if isSelectionMode {
                Button("取消") {
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
                    Button("选择") {
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
        if DatabaseManager.shared.deleteAlbum(id: album.id) {
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
             if DatabaseManager.shared.deleteAlbum(id: albumId) {
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
    @Environment(\.colorScheme) var colorScheme
    
    init(album: Album) {
        self.album = album
        appLog("AlbumCard: 创建相册卡片 '\(album.name)'，显示照片数量: \(album.count)")
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(colorScheme == .dark ? 
                      Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), 
                        radius: 8, x: 0, y: 2)
            
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
                        Text("\(album.count) 张照片")
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
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .padding(.trailing, 5)
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
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("相册信息")) {
                    TextField("相册名称", text: $albumName)
                }
            }
            .navigationTitle("创建新相册")
            .navigationBarItems(
                leading: Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("创建") {
                    if !albumName.isEmpty {
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
                    }
                }
                .disabled(albumName.isEmpty)
            )
        }
    }
}

struct ProfileView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showingPasswordSettings = false
    @State private var storageSize: String = "计算中..."
    
    var body: some View {
        NavigationView {
            VStack {
                // 用户头像
                Circle()
                    .fill(colorScheme == .dark ? 
                          Color(UIColor.systemGray5) : Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundColor(colorScheme == .dark ? 
                                             Color.gray.opacity(0.8) : .gray)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), 
                            radius: 5, x: 0, y: 2)
                    .padding(.top, 30)
                
                Text("用户")
                    .font(.title)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.top, 8)
                
                // 选项列表
                List {
                    Section {
                        HStack {
                            Label("存储空间", systemImage: "externaldrive.fill")
                            Spacer()
                            Text(storageSize)
                                .foregroundColor(.gray)
                        }
                        
                        Button(action: {
                            showingPasswordSettings = true
                        }) {
                            HStack {
                                Label("计算器密码", systemImage: "lock.shield")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Section {
                        HStack {
                            Label("关于", systemImage: "info.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("我的")
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
            .sheet(isPresented: $showingPasswordSettings) {
                PasswordSettingsView()
            }
            .onAppear {
                calculateStorageSize()
            }
        }
    }
    
    private func calculateStorageSize() {
        // 在后台线程计算存储空间
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let libraryPath = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            
            var totalSize: UInt64 = 0
            
            // 计算 Documents 目录大小
            if let documentsSize = try? fileManager.allocatedSizeOfDirectory(at: documentsPath) {
                totalSize += documentsSize
            }
            
            // 计算 Library 目录大小
            if let librarySize = try? fileManager.allocatedSizeOfDirectory(at: libraryPath) {
                totalSize += librarySize
            }
            
            // 在主线程更新 UI
            DispatchQueue.main.async {
                self.storageSize = formatFileSize(totalSize)
            }
        }
    }
    
    private func formatFileSize(_ size: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

// 扩展 FileManager 以计算目录大小
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
