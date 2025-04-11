import SwiftUI
import PhotosUI
import Photos

// MARK: - Thumbnail Cache Manager
class ThumbnailCacheManager: ObservableObject {
    let memoryCache = NSCache<NSUUID, UIImage>()
    private var diskCacheUrl: URL? = nil
    private var loadingTasks = Set<UUID>() // Track photos currently being loaded
    private let lock = NSLock() // Protect access to loadingTasks
    private let fileManager = FileManager.default
    private let diskQueue = DispatchQueue(label: "com.yourapp.thumbnailDiskQueue", qos: .utility)

    init() {
        // Configure memory cache limits (Significantly Reduced)
        memoryCache.countLimit = 150 // Keep fewer decoded thumbnails in RAM
        memoryCache.totalCostLimit = 1024 * 1024 * 30 // Limit memory footprint to ~30MB

        // Setup disk cache directory
        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            diskCacheUrl = cachesDirectory.appendingPathComponent("thumbnail_cache")
            do {
                if let url = diskCacheUrl, !fileManager.fileExists(atPath: url.path) {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                    appLog("ThumbnailCacheManager: Created disk cache directory at \(url.path)")
                } else if let url = diskCacheUrl {
                    appLog("ThumbnailCacheManager: Disk cache directory exists at \(url.path)")
                }
            } catch {
                appLog("ThumbnailCacheManager: Error creating disk cache directory: \(error)")
                diskCacheUrl = nil // Disable disk cache if creation fails
            }
        } else {
            appLog("ThumbnailCacheManager: Could not find caches directory. Disk cache disabled.")
        }

        appLog("ThumbnailCacheManager initialized. Memory Count limit: \(memoryCache.countLimit), Memory Cost limit: \(memoryCache.totalCostLimit), Disk cache enabled: \(diskCacheUrl != nil)")
    }

    // Get file URL for a photo ID in the disk cache
    private func diskCacheUrl(for photoId: UUID) -> URL? {
        // Use a consistent file extension, e.g., .jpg
        // Using UUID string directly might be okay for Cache dir, but consider hashing if needed.
        return diskCacheUrl?.appendingPathComponent("\(photoId.uuidString).jpg")
    }

    // Function to get from cache or start loading
    func getThumbnail(for photo: Photo, completion: @escaping (UIImage?) -> Void) {
        let photoId = photo.id

        // 1. Check memory cache first
        if let cachedImage = memoryCache.object(forKey: photoId as NSUUID) {
            // appLog("ThumbnailCacheManager: Memory Cache hit for \(photo.fileName)")
            completion(cachedImage)
            return
        }

        // 2. Check disk cache (asynchronously)
        if let fileUrl = diskCacheUrl(for: photoId) {
            diskQueue.async { // 修复：使用diskQueue异步检查磁盘缓存
                if self.fileManager.fileExists(atPath: fileUrl.path) {
                    // appLog("ThumbnailCacheManager: Disk Cache hit for \(photo.fileName)")
                    if let data = try? Data(contentsOf: fileUrl), let image = UIImage(data: data) {
                        // Store in memory cache
                        let cost = Int(image.size.width * image.size.height * image.scale * 4)
                        self.memoryCache.setObject(image, forKey: photoId as NSUUID, cost: cost)
                        // Return on main thread
                        DispatchQueue.main.async {
                            completion(image)
                        }
                        return // Found in disk cache
                    } else {
                        appLog("ThumbnailCacheManager: Error reading/decoding disk cache for \(photo.fileName)")
                        // Optionally delete corrupted file
                        try? self.fileManager.removeItem(at: fileUrl)
                    }
                }
                
                // 切换到主线程调用生成缩略图的方法
                DispatchQueue.main.async {
                    // Not found in disk cache or failed to load, proceed to generation
                    self.generateAndCacheThumbnail(for: photo, completion: completion)
                }
            }
        } else {
            // Disk cache disabled, proceed to generation
            generateAndCacheThumbnail(for: photo, completion: completion)
        }
    }

    // Helper to handle generation and caching logic
    private func generateAndCacheThumbnail(for photo: Photo, completion: @escaping (UIImage?) -> Void) {
        let photoId = photo.id

        // Check if already loading (thread-safe access)
        lock.lock()
        if loadingTasks.contains(photoId) {
            lock.unlock()
            // appLog("ThumbnailCacheManager: Already loading \(photo.fileName), waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Simple retry
                self.getThumbnail(for: photo, completion: completion)
            }
            return
        }
        loadingTasks.insert(photoId)
        lock.unlock()

        // appLog("ThumbnailCacheManager: Generating thumbnail for \(photo.fileName)")
        Task.detached(priority: .userInitiated) {
            let loadedThumbnail = PhotoManager.shared.getThumbnail(for: photo)

            if let image = loadedThumbnail {
                // Store in memory cache
                let cost = Int(image.size.width * image.size.height * image.scale * 4)
                self.memoryCache.setObject(image, forKey: photoId as NSUUID, cost: cost)
                // appLog("ThumbnailCacheManager: Stored \(photo.fileName) in memory cache.")

                // Store in disk cache (async)
                if let fileUrl = self.diskCacheUrl(for: photoId) {
                    // Use jpegData for consistency, adjust quality as needed
                    if let data = image.jpegData(compressionQuality: 0.8) { 
                        self.diskQueue.async {
                            do {
                                try data.write(to: fileUrl)
                                // appLog("ThumbnailCacheManager: Stored \(photo.fileName) in disk cache.")
                            } catch {
                                appLog("ThumbnailCacheManager: Failed to write disk cache for \(photo.fileName): \(error)")
                            }
                        }
                    } else {
                         appLog("ThumbnailCacheManager: Failed to get JPEG data for disk cache for \(photo.fileName)")
                    }
                }
            }

            // Remove from loading tasks
            self.lock.lock()
            self.loadingTasks.remove(photoId)
            self.lock.unlock()

            // Call completion handler on main thread
            await MainActor.run {
                completion(loadedThumbnail)
            }
        }
    }

    // Preload function
    func preloadThumbnails(for photos: [Photo]) {
        appLog("ThumbnailCacheManager: Starting preload for \(photos.count) photos.")
        // 限制同时预加载的图片数量
        let maxConcurrentPreloads = 3 // Keep this relatively low for background tasks

        // 使用信号量控制并发
        let preloadSemaphore = DispatchSemaphore(value: maxConcurrentPreloads)
        let preloadGroup = DispatchGroup()

        Task { // Use a single outer Task to manage the loop and group notification
            for photo in photos {
                let photoId = photo.id

                // 1. Check memory cache (sync)
                if memoryCache.object(forKey: photoId as NSUUID) != nil {
                    // appLog("ThumbnailCacheManager (Preload): Memory Hit for \(photo.fileName). Skipping.")
                    continue
                }

                // Wait for a slot
                preloadSemaphore.wait()
                preloadGroup.enter()

                // Launch detached task for disk check & generation
                Task.detached(priority: .background) {
                    var foundOrGenerated = false

                    // 2. Check disk cache (async on diskQueue)
                    if let fileUrl = self.diskCacheUrl(for: photoId) {
                        let fileExists = await Task { // Check file existence on disk queue
                            return await withCheckedContinuation { cont in
                                self.diskQueue.async {
                                    cont.resume(returning: self.fileManager.fileExists(atPath: fileUrl.path))
                                }
                            }
                        }.value

                        if fileExists {
                            // appLog("ThumbnailCacheManager (Preload): Disk Hit for \(photo.fileName). Skipping generation.")
                            foundOrGenerated = true
                        }
                    }

                    // 3. Generate if not found and not already loading
                    if !foundOrGenerated {
                        // Use await with the checkAndGenerateForPreload function which now MUST call its completion
                        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                            self.checkAndGenerateForPreload(photo: photo) {
                                foundOrGenerated = true // Mark as handled
                                cont.resume() // Resume the continuation when checkAndGenerate completes
                            }
                        }
                    }

                    // Task finished, release semaphore and leave group
                    preloadSemaphore.signal()
                    preloadGroup.leave()
                } // End detached Task
            } // End for loop

            // Notify main thread when all tasks associated with the group are done
            preloadGroup.notify(queue: DispatchQueue.main) {
                appLog("ThumbnailCacheManager: All preload tasks completed.")
            }
        } // End outer Task
    }

    private func checkAndGenerateForPreload(photo: Photo, completion: @escaping () -> Void) { // Ensure completion is defined
         let photoId = photo.id

         lock.lock()
         let isLoading = loadingTasks.contains(photoId)
         if !isLoading {
             loadingTasks.insert(photoId) // Mark as loading immediately
         }
         lock.unlock()

         if !isLoading {
             // appLog("ThumbnailCacheManager (Preload): Cache miss & not loading \(photo.fileName). Starting background generation.")
             Task.detached(priority: .background) { // Use background priority for preloading
                 let loadedThumbnail = PhotoManager.shared.getThumbnail(for: photo)
                 if let image = loadedThumbnail {
                     // Store in memory
                     let cost = Int(image.size.width * image.size.height * image.scale * 4)
                     self.memoryCache.setObject(image, forKey: photoId as NSUUID, cost: cost)

                     // Store on disk
                     if let fileUrl = self.diskCacheUrl(for: photoId), let data = image.jpegData(compressionQuality: 0.8) {
                         self.diskQueue.async {
                             do {
                                 try data.write(to: fileUrl)
                             } catch {
                                 appLog("ThumbnailCacheManager (Preload): Failed to write disk cache for \(photo.fileName): \(error)")
                             }
                         }
                     }
                 } else {
                     // appLog("ThumbnailCacheManager (Preload): Failed to generate \(photo.fileName).")
                 }
                 // Remove from loading tasks regardless of success/failure
                 self.lock.lock()
                 self.loadingTasks.remove(photoId)
                 self.lock.unlock()

                 // !!! Crucial: Call completion handler !!!
                 completion()
             }
         } else {
             // appLog("ThumbnailCacheManager (Preload): \(photo.fileName) is already loading. Skipping.")
             // !!! Crucial: Call completion handler even if skipping !!!
             completion()
         }
    }
}

// MARK: - Async Thumbnail View
struct AsyncThumbnailView: View {
    let photo: Photo
    @ObservedObject var cacheManager: ThumbnailCacheManager // Inject cache manager
    @State private var thumbnail: UIImage? = nil
    @State private var isLoading = false // Track loading state per image

    // Initializer to accept the cache manager
    init(photo: Photo, cacheManager: ThumbnailCacheManager) {
        self.photo = photo
        self.cacheManager = cacheManager
        // Try to get from cache immediately on init
        self._thumbnail = State(initialValue: cacheManager.memoryCache.object(forKey: photo.id as NSUUID))
         // appLog("AsyncThumbnailView init: \(photo.fileName) - Initial cache check: \(self.thumbnail != nil ? "Hit" : "Miss")")
         // If cache miss, set loading true initially
         if self.thumbnail == nil {
             self._isLoading = State(initialValue: true)
         }
    }

    var body: some View {
        Group {
            if let image = thumbnail {
                Image(uiImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder view
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        if isLoading {
                             ProgressView()
                                 .scaleEffect(0.8) // Smaller progress view
                        }
                    }
            }
        }
        .frame(width: UIScreen.main.bounds.width / 4 - 10, height: UIScreen.main.bounds.width / 4 - 10) // Keep frame consistent
        .cornerRadius(6)
        .clipped()
        .task { // Use .task for automatic cancellation and view lifecycle
            // Only attempt load if thumbnail wasn't found in cache during init
            if thumbnail == nil {
                 appLog("AsyncThumbnailView .task: Cache miss for \(photo.fileName), calling cacheManager.getThumbnail")
                 await loadThumbnailFromManager()
            } else {
                 // appLog("AsyncThumbnailView .task: Cache hit for \(photo.fileName), load not needed")
                 // Ensure loading indicator is off if cache hit happened after init but before task
                 if isLoading {
                     isLoading = false
                 }
            }
        }
        .onDisappear {
            // Optional: Cancel any ongoing loading task specifically for this view instance
            // This requires more complex task management within the cacheManager or view
            // appLog("AsyncThumbnailView onDisappear: \(photo.fileName)")
        }
    }

    // Changed to use the cache manager's method
    private func loadThumbnailFromManager() async {
        await MainActor.run { isLoading = true }
        
        // Use Combine or async/await with a continuation if cacheManager provides async interface
        // For now, using completion handler approach:
        let loaded = await Task { // Wrap completion handler in Task for await
            return await withCheckedContinuation { continuation in
                cacheManager.getThumbnail(for: photo) { image in
                    continuation.resume(returning: image)
                }
            }
        }.value
        
        await MainActor.run {
            if let loadedImage = loaded {
                self.thumbnail = loadedImage
                // appLog("AsyncThumbnailView: Loaded thumbnail for \(photo.fileName) via cache manager")
            } else {
                appLog("AsyncThumbnailView: Failed to load thumbnail for \(photo.fileName) via cache manager")
            }
            isLoading = false
        }
    }

    // Removed old loadThumbnail and getExistingThumbnail methods
}

// MARK: - PhotoGridView
// 注意：此视图应该嵌套在NavigationStack或NavigationView中使用，而不是在此处嵌套
// 例如:
// NavigationStack {
//    PhotoGridView(album: selectedAlbum)
// }
struct PhotoGridView: View {
    let album: Album
    @State private var gridLayout = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    @Environment(\.colorScheme) var colorScheme
    @State private var photos: [Photo] = []
    @State private var updatedAlbum: Album
    @State private var isImporting = false
    @State private var selectedItems = [PhotosPickerItem]()
    @State private var isLoading = false
    @State private var selectedPhoto: Photo? = nil
    @State private var preloadedThumbnails = false
    
    // 新增 State 用于删除确认
    @State private var showDeleteFromLibraryAlert = false
    @State private var successfullyImportedIdentifiers: [String] = []
    @State private var deleteAlertMessage = "" // 用于显示不同的删除结果或权限提示
    @State private var showResultAlert = false // 控制结果/权限弹窗
    
    @State private var isSelectionMode = false
    @State private var selectedPhotoIDs = Set<UUID>()
    @State private var showMultiDeleteAlert = false // 用于批量删除确认
    @State private var photoToDeleteSingle: Photo? = nil
    @State private var showSingleDeleteAlert = false
    @State private var showAlbumSelectionSheet = false // <-- ADD State for sheet
    
    // Create the thumbnail cache manager
    @StateObject private var thumbnailCacheManager = ThumbnailCacheManager()
    
    init(album: Album) {
        self.album = album
        _updatedAlbum = State(initialValue: album)
        appLog("PhotoGridView: 初始化 - 相册'\(album.name)'包含\(album.count)张照片")
    }
    
    var body: some View {
        ZStack {
            contentView
            loadingView
        }
        .navigationTitle(navigationTitle)
        .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        // 添加iOS 16的工具栏背景优化
        .if16Available { view in
            view.toolbarBackground(.visible, for: .navigationBar)
        }
        .toolbar {
            // Log before the condition
            let _ = appLog("Toolbar evaluated. isSelectionMode = \\(isSelectionMode)")

            // Leading Item (Cancel button in selection mode)
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelectionMode {
                    Button("取消") {
                        exitSelectionMode()
                    }
                }
                // No else needed, shows nothing when not in selection mode
            }

            // Trailing Items - Use individual ToolbarItems
            if isSelectionMode {
                // Delete Button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if !selectedPhotoIDs.isEmpty {
                             showMultiDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedPhotoIDs.isEmpty)
                    .foregroundColor(selectedPhotoIDs.isEmpty ? .gray : .red)
                }

                // Share/Move Menu
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareSelectedPhotosExternally()
                        } label: {
                            Label("分享到...", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedPhotoIDs.isEmpty)

                        Button {
                            showAlbumSelectionSheet = true
                        } label: {
                            Label("移动到相册...", systemImage: "folder")
                        }
                        .disabled(selectedPhotoIDs.isEmpty)

                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(selectedPhotoIDs.isEmpty)
                }
            } else {
                // Place Select and Import buttons in separate ToolbarItems
                // Place "Select" button first (appears further right)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("选择") {
                        enterSelectionMode()
                    }
                }
                // Place PhotosPicker ("+") next
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(
                        selection: $selectedItems,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "plus")
                    }
                    .onChange(of: selectedItems) { newItems in
                        importPhotos(from: newItems)
                    }
                }
            }
        }
        .sheet(isPresented: $showAlbumSelectionSheet) {
            // Present the AlbumSelectionView
            AlbumSelectionView(selectedPhotoIDs: selectedPhotoIDs, currentAlbumId: album.id) { destinationAlbumId in
                // This closure is called when an album is selected in the sheet
                moveSelectedPhotos(to: destinationAlbumId)
                showAlbumSelectionSheet = false // Dismiss the sheet
            }
        }
        .fullScreenCover(item: $selectedPhoto, onDismiss: {
            appLog("照片详情视图已关闭 (item dismissed)")
        }) { photo in
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                let _ = appLog("fullScreenCover(item:): Creating ImageDetailView for \\(photo.fileName) at index \\(index)")
                ImageDetailView(
                    photoIndex: index,
                    allPhotos: photos,
                    onDelete: { photoToDelete in
                        if let indexToDelete = photos.firstIndex(where: { $0.id == photoToDelete.id }) {
                            photos.remove(at: indexToDelete)
                            loadPhotos()
                            if photos.isEmpty || selectedPhoto?.id == photoToDelete.id {
                                selectedPhoto = nil
                            }
                        }
                    },
                    thumbnailCacheManager: thumbnailCacheManager // Pass the manager
                )
                .onAppear {
                    appLog("ImageDetailView appeared via fullScreenCover(item:)")
                }
                .ignoresSafeArea()
            } else {
                let _ = appLog("fullScreenCover(item:): Error - Could not find index for presented photo \\(photo.fileName)")
                EmptyView()
            }
        }
        .onAppear {
            appLog("PhotoGridView onAppear - 开始加载照片")
            loadPhotos()
        }
        .alert("删除已导入的照片?", isPresented: $showDeleteFromLibraryAlert) {
            Button("删除", role: .destructive) {
                deleteImportedPhotosFromLibrary()
            }
            Button("保留", role: .cancel) {
                successfullyImportedIdentifiers = []
                appLog("User chose not to delete photos from library.")
            }
        } message: {
            Text("您想从系统\"照片\"应用中删除刚刚导入的 \(successfullyImportedIdentifiers.count) 张照片吗？此操作不可撤销。")
        }
        .alert("照片库操作结果", isPresented: $showResultAlert, actions: {
            Button("好的") {
                deleteAlertMessage = ""
                showResultAlert = false
            }
        }, message: {
            Text(deleteAlertMessage)
        })
        .alert("删除所选照片?", isPresented: $showMultiDeleteAlert) {
            Button("删除", role: .destructive) {
                deleteSelectedPhotos()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除选中的 \(selectedPhotoIDs.count) 张照片吗？此操作将从应用内部删除这些照片，但不会影响系统相册。")
        }
        .alert("删除照片", isPresented: $showSingleDeleteAlert) {
            Button("删除", role: .destructive) {
                executeDeleteSinglePhoto()
            }
            Button("取消", role: .cancel) {
                photoToDeleteSingle = nil // 清理
            }
        } message: {
            Text("确定要删除这张照片吗？此操作将从应用内部删除照片，但不会影响系统相册。")
        }
    }
    
    // 内容视图 - 拆分复杂表达式
    private var contentView: some View {
        Group {
            if photos.isEmpty && !isLoading {
                emptyStateView
            } else {
                photoGridView
            }
        }
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
            
            Text("暂无图片")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("点击右上角的"+"按钮导入照片")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 照片网格视图
    private var photoGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridLayout, spacing: 6) {
                ForEach(photos) { photo in
                    gridItemView(for: photo)
                }
            }
            .padding(8)
        }
    }
    
    // 单个网格项目视图
    private func gridItemView(for photo: Photo) -> some View {
        Button(action: {
            if isSelectionMode {
                toggleSelection(for: photo)
            } else {
                appLog("用户点击缩略图: \(photo.fileName)")
                selectedPhoto = photo
                appLog("Button Action: Set selectedPhoto to \(photo.fileName) to trigger cover")
            }
        }) {
            photoThumbnailView(for: photo)
                .overlay(selectionOverlay(for: photo))
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if !isSelectionMode {
                Button(role: .destructive) {
                    deleteSinglePhotoConfirmation(photo)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
    
    // 照片缩略图视图
    private func photoThumbnailView(for photo: Photo) -> some View {
        // Pass the cache manager to the thumbnail view
        AsyncThumbnailView(photo: photo, cacheManager: thumbnailCacheManager)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    // 选择覆盖层视图
    private func selectionOverlay(for photo: Photo) -> some View {
        Group {
            if isSelectionMode {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(selectedPhotoIDs.contains(photo.id) ? 0.3 : 0)

                    Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.white)
                        .background(Circle().fill(selectedPhotoIDs.contains(photo.id) ? Color.blue : Color.black.opacity(0.3)))
                        .clipShape(Circle())
                        .font(.system(size: 20))
                        .padding(4)
                }
                .cornerRadius(6)
                .animation(.easeInOut(duration: 0.15), value: selectedPhotoIDs.contains(photo.id))
            }
        }
    }
    
    // 切换照片选中状态
    private func toggleSelection(for photo: Photo) {
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
        } else {
            selectedPhotoIDs.insert(photo.id)
        }
    }
    
    // 顶部按钮
    private var trailingButtons: some View {
        HStack {
            if isSelectionMode {
                EmptyView()
            } else {
                Button("选择") {
                    enterSelectionMode()
                }

                PhotosPicker(
                    selection: $selectedItems,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "plus")
                }
                .onChange(of: selectedItems) { newItems in
                    importPhotos(from: newItems)
                }
            }
        }
    }
    
    // 加载指示器视图
    private var loadingView: some View {
        Group {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        
                        Text("正在导入照片...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(25)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Color.gray.opacity(0.7)))
                }
            }
        }
    }
    
    // 加载相册中的照片
    private func loadPhotos() {
        appLog("PhotoGridView: 开始加载相册 '\(album.name)' 的照片")
        photos = PhotoManager.shared.getPhotos(fromAlbum: album.id)
        
        // 添加日志，记录从PhotoManager获取的实际照片数量
        appLog("PhotoGridView: loadPhotos - 获取到相册'\(album.name)'的照片数量: \(photos.count)，数据库中记录的数量: \(album.count)")
        
        // Trigger thumbnail preloading after photos are loaded
        if !photos.isEmpty {
            thumbnailCacheManager.preloadThumbnails(for: photos)
        }
        
        // 更新相册信息
        let newAlbum = Album(
            id: album.id,
            name: album.name,
            coverImage: album.coverImage,
            count: photos.count,
            createdAt: album.createdAt
        )
        
        appLog("PhotoGridView: loadPhotos - 准备更新相册'\(album.name)'的照片数量从 \(album.count) 到 \(photos.count)")
        
        if DatabaseManager.shared.updateAlbum(newAlbum) {
            updatedAlbum = newAlbum
            appLog("PhotoGridView: loadPhotos - 数据库更新成功，更新后的相册'\(updatedAlbum.name)'照片数量: \(updatedAlbum.count)")
            
            // 确保通知发送后，等待一小段时间再继续
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .didUpdateAlbumList, object: nil)
                appLog("PhotoGridView: loadPhotos - 已发送相册更新通知")
            }
        } else {
            appLog("PhotoGridView: loadPhotos - 数据库更新失败")
        }
    }
    
    // 导入照片
    private func importPhotos(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        isLoading = true
        var successfullyImportedIdentifiers: [String] = [] // 本次成功导入的系统标识符
        var successfullySavedPhotos: [Photo] = [] // 本次成功保存的 Photo 对象
        var failedIdentifiers: [String: String] = [:] // 记录失败的标识符和原因

        Task(priority: .userInitiated) { // 使用 userInitiated 优先级
            appLog("开始导入 \(items.count) 张照片...")
            
            // 按顺序处理每个选中的项目
            for (index, item) in items.enumerated() {
                guard let identifier = item.itemIdentifier else {
                    appLog("导入警告 (项 \(index + 1)/\(items.count)): 无法获取照片标识符，已跳过。")
                    failedIdentifiers["未知标识符_\(index)"] = "无法获取标识符"
                    continue
                }
                
                appLog("开始处理照片 (项 \(index + 1)/\(items.count)): ID = \(identifier)")
                
                // 1. 获取元数据 (文件名和日期)
                var originalFileName = "未知文件名_\(UUID().uuidString.prefix(6))" // 提供唯一默认名
                var dateTaken: Date? = nil
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                if let asset = fetchResult.firstObject {
                    let resources = PHAssetResource.assetResources(for: asset)
                    if let resource = resources.first { originalFileName = resource.originalFilename }
                    dateTaken = asset.creationDate // 使用创建日期
                    appLog("  - 获取元数据成功: 文件名='\(originalFileName)', 日期=\(dateTaken?.description ?? "无")")
                } else {
                    appLog("  - 警告: 无法从 PhotoKit 获取 PHAsset: \(identifier)")
                    // 即使无法获取，也继续尝试加载数据
                }
                
                // 2. 加载照片数据
                var loadedData: Data? = nil
                do {
                    loadedData = try await item.loadTransferable(type: Data.self)
                    if let data = loadedData, !data.isEmpty {
                        appLog("  - 加载照片数据成功: 大小 = \(data.count) 字节")
                    } else {
                        appLog("  - 错误: 加载的照片数据为空或失败: \(identifier)")
                        failedIdentifiers[identifier] = "加载数据失败或为空"
                        loadedData = nil // 确保为 nil
                    }
                } catch {
                    appLog("  - 错误: 加载 transferable data 时发生异常: \(identifier), 错误: \(error)")
                    failedIdentifiers[identifier] = "加载数据异常: \(error.localizedDescription)"
                    loadedData = nil
                }
                
                // 如果数据加载失败，则跳过此照片
                guard let imageData = loadedData else {
                    appLog("  - 跳过照片 \(identifier) 因为数据加载失败。")
                    continue
                }
                
                // 3. 创建 UIImage
                guard let image = UIImage(data: imageData) else {
                    appLog("  - 错误: 无法从加载的数据创建 UIImage: \(identifier)")
                    failedIdentifiers[identifier] = "无法创建UIImage"
                    continue
                }
                appLog("  - 创建 UIImage 成功: 尺寸 = \(image.size)")
                
                // 4. 保存照片 (调用 PhotoManager)
                appLog("  - 调用 PhotoManager.savePhoto 保存照片...")
                if let savedPhoto = PhotoManager.shared.savePhoto(image: image, toAlbum: album.id, originalFileName: originalFileName, dateTaken: dateTaken) {
                    appLog("  - 保存照片成功: \(identifier), 返回 Photo 对象: \(savedPhoto.fileName)")
                    successfullySavedPhotos.append(savedPhoto)
                    successfullyImportedIdentifiers.append(identifier)
                } else {
                    appLog("  - 错误: PhotoManager.savePhoto 返回 nil，保存失败: \(identifier)")
                    failedIdentifiers[identifier] = "PhotoManager 保存失败 (返回nil)"
                }
                
                appLog("完成处理照片 (项 \(index + 1)/\(items.count)): ID = \(identifier)")
            }
            
            // 5. 导入过程结束，记录总结
            appLog("照片导入流程结束。总共尝试 \(items.count) 项，成功保存 \(successfullySavedPhotos.count) 张，失败 \(failedIdentifiers.count) 张。")
            if !failedIdentifiers.isEmpty {
                appLog("失败详情: \(failedIdentifiers)")
            }

            // 6. 更新 UI (切换回主线程)
            await MainActor.run {
                self.isLoading = false

                if !successfullySavedPhotos.isEmpty {
                    appLog("Import successful. Notification should trigger AlbumsListView refresh.") // Update log message
                    // 稍作延迟以确保数据一致性，然后刷新
                    // NOTE: Removed the redundant self.loadPhotos() call here.
                    // AlbumsListView's .onReceive will handle the refresh.
                    
                    // 添加loadPhotos()调用，确保导入后刷新照片列表
                    self.loadPhotos()
                    appLog("Called loadPhotos() to refresh the photo grid after import")

                    // Prepare to show the delete prompt
                    self.successfullyImportedIdentifiers = successfullyImportedIdentifiers
                    self.showDeleteFromLibraryAlert = true // Show delete prompt
                    appLog("Will prompt to delete \\(successfullyImportedIdentifiers.count) photos from library.")
                } else {
                    appLog("没有照片成功保存，显示导入失败提示。")
                    self.deleteAlertMessage = "照片导入失败。尝试了 \\(items.count) 张，成功 0 张。详情请查看日志。"
                    if !failedIdentifiers.isEmpty {
                        // 只取第一个失败原因作为示例给用户看
                        if let firstError = failedIdentifiers.first?.value {
                            self.deleteAlertMessage += "\n(可能原因: \(firstError))"
                        }
                    }
                    self.showResultAlert = true
                }
            }
        }
    }
    
    // 删除单张照片 (现在先触发确认) - 重命名以区分
    private func deleteSinglePhotoConfirmation(_ photo: Photo) {
        self.photoToDeleteSingle = photo
        self.showSingleDeleteAlert = true
    }

    private func executeDeleteSinglePhoto() {
        guard let photo = photoToDeleteSingle else { return }
        appLog("Executing delete for single photo: \(photo.fileName)")
        if PhotoManager.shared.deletePhoto(photo) {
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                photos.remove(at: index)
                loadPhotos() // 重新加载以更新计数
                // 不需要处理 selectedPhoto，因为这是通过 context menu 触发的
            }
        }
        photoToDeleteSingle = nil // 清理
    }

    // 批量删除选中的照片
    private func deleteSelectedPhotos() {
        let idsToDelete = selectedPhotoIDs // 复制一份，因为要修改 photos 数组
        var deletedCount = 0
        appLog("Attempting to delete \(idsToDelete.count) selected photos.")

        // 找到所有对应的 Photo 对象
        let photosToDelete = photos.filter { idsToDelete.contains($0.id) }

        for photo in photosToDelete {
            if PhotoManager.shared.deletePhoto(photo) {
                deletedCount += 1
                appLog("Successfully deleted photo: \(photo.fileName)")
            } else {
                appLog("Failed to delete photo: \(photo.fileName)")
                // 可以考虑给用户一些反馈
            }
        }

        appLog("Finished deleting. Deleted \(deletedCount) out of \(idsToDelete.count) photos.")

        // 清理并退出选择模式
        selectedPhotoIDs.removeAll()
        isSelectionMode = false
        loadPhotos() // 刷新视图和相册计数
    }
    
    // 根据是否在选择模式决定导航栏标题
    private var navigationTitle: String {
        if isSelectionMode {
            return "已选择 \(selectedPhotoIDs.count) 项"
        } else {
            return updatedAlbum.name
        }
    }

    // 进入选择模式
    private func enterSelectionMode() {
        isSelectionMode = true
        selectedPhotoIDs.removeAll() // 清空之前的选择
        appLog("enterSelectionMode called. isSelectionMode is now TRUE")
    }

    // 退出选择模式
    private func exitSelectionMode() {
        isSelectionMode = false
        selectedPhotoIDs.removeAll()
        appLog("exitSelectionMode called. isSelectionMode is now FALSE")
    }

    // MARK: - Move Photos Function
    private func moveSelectedPhotos(to destinationAlbumId: UUID) {
        guard !selectedPhotoIDs.isEmpty else { return }
        
        // Filter the current photos array to get the full Photo objects to move
        let photosToMove = photos.filter { selectedPhotoIDs.contains($0.id) }
        
        guard !photosToMove.isEmpty else {
            appLog("moveSelectedPhotos: No matching Photo objects found for selected IDs. Aborting move.")
            // Maybe clear selection and show an error?
            exitSelectionMode()
            return
        }

        appLog("Attempting to move \(photosToMove.count) photos to album ID: \(destinationAlbumId)")

        // Call the updated movePhotos function in PhotoManager
        let success = PhotoManager.shared.movePhotos(photosToMove: photosToMove, to: destinationAlbumId)

        if success {
            appLog("Successfully moved \(photosToMove.count) photos.")
            // Show success message
            deleteAlertMessage = "已成功移动 \(photosToMove.count) 张照片。"
            showResultAlert = true
        } else {
            appLog("Failed to move some or all photos.")
            // Show potentially more specific failure message if needed
            deleteAlertMessage = "移动部分或全部照片失败，请检查日志或重试。"
            showResultAlert = true
        }

        // Cleanup and refresh
        exitSelectionMode() // Also clears selectedPhotoIDs
        loadPhotos() // Refresh the current album view
    }

    // MARK: - Sharing Functions
    private func shareSelectedPhotosExternally() {
        guard !selectedPhotoIDs.isEmpty else { return }

        appLog("Starting external share for \(selectedPhotoIDs.count) photos.")

        // Show loading indicator if needed (optional)
        // self.isSharingExternally = true 

        Task {
            var imagesToShare: [UIImage] = []
            let photosToLoad = photos.filter { selectedPhotoIDs.contains($0.id) }

            // Load images asynchronously
            for photo in photosToLoad {
                if let image = await PhotoManager.shared.loadFullImage(for: photo) {
                    imagesToShare.append(image)
                } else {
                    appLog("Warning: Failed to load full image for sharing: \(photo.fileName)")
                    // Optionally notify user about failures
                }
            }

            await MainActor.run {
                // Hide loading indicator
                // self.isSharingExternally = false

                if imagesToShare.isEmpty {
                    appLog("External Share Error: No images could be loaded.")
                    // Show an alert to the user
                    self.deleteAlertMessage = "无法加载所选照片以进行分享。"
                    self.showResultAlert = true
                    return
                }

                appLog("Successfully loaded \(imagesToShare.count) images for sharing. Presenting share sheet.")

                let activityViewController = UIActivityViewController(activityItems: imagesToShare, applicationActivities: nil)

                // Find the current key window scene to present the share sheet
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                    appLog("External Share Error: Could not find root view controller to present share sheet.")
                    self.deleteAlertMessage = "无法弹出分享窗口。"
                    self.showResultAlert = true
                    return
                }

                // Find the most appropriate view controller to present from
                var topController = rootViewController
                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }

                // Recommended for iPad compatibility
                if let popoverController = activityViewController.popoverPresentationController {
                    popoverController.sourceView = topController.view // Use the presenting view controller's view
                    // You might want to refine sourceRect based on the tapped button's position
                    popoverController.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0) 
                    popoverController.permittedArrowDirections = [] // Or specify arrow directions
                }

                topController.present(activityViewController, animated: true, completion: nil)
            }
        }
    }

    // MARK: - Delete Functions
    private func deleteImportedPhotosFromLibrary() {
        appLog("Placeholder: deleteImportedPhotosFromLibrary() called. Need to implement logic to delete from PHPhotoLibrary.")
        // 实际实现需要使用 PhotoKit 来请求权限并删除 PHAsset
        // 例如：PHPhotoLibrary.shared().performChanges(...)
        // 同时需要处理权限拒绝的情况
        self.successfullyImportedIdentifiers = [] // 清空列表，避免重复提示
        self.deleteAlertMessage = "已跳过从系统相册删除的操作（功能待实现）。"
        self.showResultAlert = true
    }
}

// MARK: - Navigation Helper 
// iOS 16及以上版本可以使用此方法来包装PhotoGridView
extension PhotoGridView {
    // 将这个视图包装在NavigationStack中使用
    func embedInNavigationStack() -> some View {
        // 使用iOS 16引入的NavigationStack替代旧的NavigationView
        if #available(iOS 16.0, *) {
            return NavigationStack {
                self
            }
        } else {
            // 对于iOS 16以下版本回退到NavigationView
            return NavigationView {
                self
            }
            .navigationViewStyle(.stack)
        }
    }
}

// MARK: - ZoomableScrollView (Helper for Image Zooming)
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        // Set up the UIScrollView
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator // for viewForZooming(in:)
        scrollView.maximumZoomScale = 4.0 // Allow up to 4x zoom
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        // Create a UIHostingController to hold the SwiftUI content
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostedView.frame = scrollView.bounds
        hostedView.backgroundColor = .clear // Make hosting view transparent
        scrollView.addSubview(hostedView)
        scrollView.backgroundColor = .clear // Make scroll view transparent

        return scrollView
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(hostingController: UIHostingController(rootView: self.content))
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Update the hosting controller's SwiftUI content
        context.coordinator.hostingController.rootView = self.content
        // Ensure the hosted view fills the scroll view
        assert(context.coordinator.hostingController.view.superview == uiView)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            // Return the view hosting the SwiftUI content for zooming
            return hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Optionally center the content if it's smaller than the scroll view bounds
            centerContent(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // You can add logic here if needed after zooming finishes
        }
        
        private func centerContent(in scrollView: UIScrollView) {
             guard let contentView = hostingController.view else { return }
             let boundsSize = scrollView.bounds.size
             var frameToCenter = contentView.frame

             // Center horizontally
             if frameToCenter.size.width < boundsSize.width {
                 frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
             } else {
                 frameToCenter.origin.x = 0
             }

             // Center vertically
             if frameToCenter.size.height < boundsSize.height {
                 frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
             } else {
                 frameToCenter.origin.y = 0
             }

             contentView.frame = frameToCenter
         }
    }
}

// MARK: - Image Detail View (Fullscreen)
struct ImageDetailView: View {
    @Environment(\.presentationMode) var presentationMode // To dismiss the view
    @State var photoIndex: Int
    let allPhotos: [Photo]
    let onDelete: (Photo) -> Void
    let thumbnailCacheManager: ThumbnailCacheManager

    @State private var fullImage: UIImage? = nil
    @State private var isLoadingFullImage = true
    @State private var barsVisible = true // State to control bar visibility
    @State private var showPhotoInfo = false // 控制照片信息弹窗显示
    @State private var dateTaken: Date? = nil // 存储照片拍摄时间

    // Computed property for the current photo based on index
    private var currentPhoto: Photo {
        guard photoIndex >= 0 && photoIndex < allPhotos.count else {
            // This should ideally not happen due to checks elsewhere, but provides a fallback
            appLog("Error: photoIndex \(photoIndex) is out of bounds (\(allPhotos.count)) in computed currentPhoto. Returning first available photo.")
            // Handle potential empty array gracefully
            return allPhotos.first ?? Photo(id: UUID(), albumId: UUID(), fileName: "error", createdAt: Date()) // Placeholder
        }
        return allPhotos[photoIndex]
    }

    // Formatter for the date display
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoadingFullImage {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let image = fullImage {
                ZoomableScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        barsVisible.toggle()
                    }
                }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                    Text("无法加载图片")
                        .foregroundColor(.white)
                }
            }

            // Top Bar
            if barsVisible {
                VStack {
                    HStack {
                        Button { presentationMode.wrappedValue.dismiss() } label: {
                            Image(systemName: "chevron.left").font(.title2).foregroundColor(.white).padding()
                        }
                        Spacer()
                        // 使用拍摄时间(如果可用)，否则使用文件创建时间
                        Text(dateTaken ?? currentPhoto.createdAt, formatter: dateFormatter)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.vertical, 5).padding(.horizontal, 10)
                        Spacer()
                        Button { 
                            showPhotoInfo = true 
                        } label: {
                            Image(systemName: "info.circle").font(.title2).foregroundColor(.white).padding()
                        }
                    }
                    .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
                    .background(Material.ultraThinMaterial.opacity(0.8))
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Bottom Bar
            if barsVisible {
                VStack {
                    Spacer()
                    HStack(spacing: 30) {
                        Spacer()
                        Button { sharePhoto() } label: {
                            VStack { Image(systemName: "square.and.arrow.up").font(.title2); Text("分享").font(.caption) }.foregroundColor(.white)
                        }
                        Spacer()
                        Button {
                            // Use computed currentPhoto
                            onDelete(currentPhoto)
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            VStack { Image(systemName: "trash").font(.title2); Text("删除").font(.caption) }.foregroundColor(.red)
                        }
                        Spacer()
                        Button { print("More button tapped for \(currentPhoto.fileName)") } label: {
                             VStack { Image(systemName: "ellipsis.circle").font(.title2); Text("更多").font(.caption) }.foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 20)
                    .padding(.horizontal).padding(.top, 15)
                    .frame(maxWidth: .infinity)
                    .background(Material.ultraThinMaterial.opacity(0.8))
                }
                 .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .gesture(DragGesture().onEnded { value in handleSwipe(translation: value.translation) })
        .onAppear {
             appLog("ImageDetailView onAppear - Index: \(photoIndex), Photo: \(currentPhoto.fileName)")
            loadFullImage()
            loadPhotoMetadata()
        }
        .onChange(of: photoIndex) { newIndex in
             // No need to update currentPhoto state here anymore
             appLog("ImageDetailView onChange photoIndex: \(newIndex)")
             loadFullImage() // Just trigger loading for the new index
             loadPhotoMetadata() // 加载新照片的元数据
        }
        .statusBar(hidden: !barsVisible)
        .sheet(isPresented: $showPhotoInfo) {
            photoInfoView
        }
    }
    
    // 照片信息弹窗视图
    private var photoInfoView: some View {
        NavigationView {
            List {
                Section(header: Text("照片信息")) {
                    HStack {
                        Text("文件名")
                        Spacer()
                        Text(currentPhoto.fileName)
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("拍摄时间")
                        Spacer()
                        Text(dateTaken ?? currentPhoto.createdAt, formatter: dateFormatter)
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("尺寸")
                        Spacer()
                        Text(PhotoManager.shared.getPhotoSizeString(for: currentPhoto))
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("文件大小")
                        Spacer()
                        Text(PhotoManager.shared.getPhotoFileSize(for: currentPhoto))
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle("照片详情", displayMode: .inline)
            .navigationBarItems(trailing: Button("完成") {
                showPhotoInfo = false
            })
        }
    }

    // 加载照片元数据
    private func loadPhotoMetadata() {
        Task {
            // 获取照片拍摄时间
            let date = PhotoManager.shared.getPhotoDateTaken(for: currentPhoto)
            await MainActor.run {
                self.dateTaken = date
            }
        }
    }

    // Updated function to load the full-resolution image based on photoIndex
    private func loadFullImage() {
        // Ensure index is valid before proceeding
        guard photoIndex >= 0 && photoIndex < allPhotos.count else {
            appLog("loadFullImage Error: photoIndex \(photoIndex) out of bounds (\(allPhotos.count)). Cannot load image.")
            isLoadingFullImage = false // Stop loading indicator
            fullImage = nil // Ensure no stale image is shown
            return
        }

        let photoToLoad = allPhotos[photoIndex] // Get the correct photo using the current index
        appLog("loadFullImage: Attempting to load index \(photoIndex), photo: \(photoToLoad.fileName)")

        isLoadingFullImage = true
        fullImage = nil

        Task.detached(priority: .userInitiated) {
            let loadedImage = await PhotoManager.shared.loadFullImage(for: photoToLoad) // Pass the correct photo object
            await MainActor.run {
                // Double-check if the index is still the same when the load finishes,
                // in case the user swiped quickly multiple times.
                if self.photoIndex < self.allPhotos.count && self.allPhotos[self.photoIndex].id == photoToLoad.id {
                    if let img = loadedImage {
                        self.fullImage = img
                        appLog("loadFullImage: Successfully loaded for index \(self.photoIndex), photo: \(photoToLoad.fileName)")
                    } else {
                        appLog("loadFullImage: Failed to load full image for index \(self.photoIndex), photo: \(photoToLoad.fileName)")
                        // Keep fullImage nil
                    }
                     self.isLoadingFullImage = false
                } else {
                     appLog("loadFullImage: Load finished for index \(self.photoIndex), photo: \(photoToLoad.fileName), but view is now showing a different photo (\(self.photoIndex)). Discarding result.")
                     // Don't update the UI if the index has changed since loading started
                     // isLoadingFullImage might still need to be set to false if no other load is pending,
                     // but it will be handled by the subsequent load triggered by onChange.
                }
            }
        }
    }

    // Function to handle swipe gestures for navigation
    private func handleSwipe(translation: CGSize) {
        let swipeThreshold: CGFloat = 50

        if translation.width < -swipeThreshold { // Swipe Left
            if photoIndex < allPhotos.count - 1 {
                 appLog("Swipe detected: Left. Old index: \(photoIndex)")
                photoIndex += 1 // This triggers onChange
                 appLog("Swipe processed: Left. New index: \(photoIndex)")
            }
        } else if translation.width > swipeThreshold { // Swipe Right
            if photoIndex > 0 {
                 appLog("Swipe detected: Right. Old index: \(photoIndex)")
                photoIndex -= 1 // This triggers onChange
                 appLog("Swipe processed: Right. New index: \(photoIndex)")
            }
        }
    }

    // Function to handle the Share action
    private func sharePhoto() {
        // Use computed currentPhoto
        let photoToShare = currentPhoto
        guard let imageToShare = fullImage else {
            appLog("Share failed: Full image not available for \(photoToShare.fileName).")
            // Maybe try loading it? Or show an error?
            // For now, just return.
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [imageToShare], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            appLog("Share failed: Could not find root view controller.")
            return
        }
        rootViewController.present(activityViewController, animated: true, completion: nil)
        appLog("Presenting share sheet for \(photoToShare.fileName)")
    }
}

// MARK: - Swipe Gesture Extension (Already exists at the end of the file, removing the ZoomableScrollView from here)
// extension View {
//     func addSwipeGesture(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) -> some View {
//         self.gesture(
//             DragGesture(minimumDistance: 20, coordinateSpace: .global)
//                 .onEnded { value in
//                     let horizontalAmount = value.translation.width
//                     let verticalAmount = value.translation.height
                    
//                     if abs(horizontalAmount) > abs(verticalAmount) {
//                         if horizontalAmount < 0 {
//                             onSwipeLeft()
//                         } else {
//                             onSwipeRight()
//                         }
//                     }
//                 }
//         )
//     }
// }

// MARK: - iOS 16 Conditional Modifiers
extension View {
    @ViewBuilder
    func if16Available<Content: View>(_ transform: (Self) -> Content) -> some View {
        if #available(iOS 16.0, *) {
            transform(self)
        } else {
            self
        }
    }
}

