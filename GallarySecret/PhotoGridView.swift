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
            diskQueue.async { // Perform disk check off the main thread
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
                // Not found in disk cache or failed to load, proceed to generation
                self.generateAndCacheThumbnail(for: photo, completion: completion)
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
        for photo in photos {
            let photoId = photo.id

            // 1. Check memory cache
            if memoryCache.object(forKey: photoId as NSUUID) != nil {
                // appLog("ThumbnailCacheManager (Preload): Memory Hit for \(photo.fileName). Skipping.")
                continue
            }

            // 2. Check disk cache (async is okay for preload)
            if let fileUrl = diskCacheUrl(for: photoId) {
                 diskQueue.async {
                     if self.fileManager.fileExists(atPath: fileUrl.path) {
                         // appLog("ThumbnailCacheManager (Preload): Disk Hit for \(photo.fileName). Skipping generation.")
                         // Optional: Could load into memory here if desired
                         return
                     }
                     // Not on disk, proceed to check loading state and maybe generate
                     self.checkAndGenerateForPreload(photo: photo)
                 }
            } else {
                 // Disk cache disabled, check loading state and maybe generate
                 checkAndGenerateForPreload(photo: photo)
            }
        }
    }
    
    private func checkAndGenerateForPreload(photo: Photo) {
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
             }
         } else {
             // appLog("ThumbnailCacheManager (Preload): \(photo.fileName) is already loading. Skipping.")
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
    
    // Create the thumbnail cache manager
    @StateObject private var thumbnailCacheManager = ThumbnailCacheManager()
    
    init(album: Album) {
        self.album = album
        _updatedAlbum = State(initialValue: album)
    }
    
    var body: some View {
        ZStack {
            contentView
            loadingView
        }
        .navigationTitle(navigationTitle)
        .navigationBarItems(leading: leadingNavigationButton, trailing: trailingButtons)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if isSelectionMode {
                    Spacer()
                    Button("删除 (\(selectedPhotoIDs.count))") {
                        if !selectedPhotoIDs.isEmpty {
                             showMultiDeleteAlert = true
                        }
                    }
                    .disabled(selectedPhotoIDs.isEmpty)
                    .foregroundColor(selectedPhotoIDs.isEmpty ? .gray : .red)
                }
            }
        }
        .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        .fullScreenCover(item: $selectedPhoto, onDismiss: {
            appLog("照片详情视图已关闭 (item dismissed)")
        }) { photo in
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                let _ = appLog("fullScreenCover(item:): Creating ImageDetailView for \(photo.fileName) at index \(index)")
                ImageDetailView(
                    currentPhoto: photo,
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
                let _ = appLog("fullScreenCover(item:): Error - Could not find index for presented photo \(photo.fileName)")
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
        photos = PhotoManager.shared.getPhotos(fromAlbum: album.id)
        
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
        
        if DatabaseManager.shared.updateAlbum(newAlbum) {
            updatedAlbum = newAlbum
        }
    }
    
    // 导入照片
    private func importPhotos(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        isLoading = true
        var importedIdentifiersSuccess: [String] = [] // 改为局部变量

        Task {
            var newPhotos: [Photo] = []
            
            for item in items {
                guard let identifier = item.itemIdentifier else {
                    appLog("Warning: Could not get itemIdentifier for a selected photo.")
                    continue
                }

                do {
                    // 修改：合并 data 的解包和 UIImage 的创建
                    if let data = try await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) { 
                        // 尝试保存到 App 内部存储
                        if let photo = PhotoManager.shared.savePhoto(image: image, toAlbum: album.id) {
                            newPhotos.append(photo)
                            importedIdentifiersSuccess.append(identifier) // 记录成功导入的系统标识符
                            appLog("Successfully imported photo with identifier: \(identifier)")
                        } else {
                             appLog("Warning: Failed to save photo data internally for identifier: \(identifier)")
                        }
                    } else {
                         // 修改：统一处理加载数据失败或创建 UIImage 失败的情况
                         appLog("Warning: Failed to load data or create UIImage for identifier: \(identifier)")
                    }
                } catch {
                    appLog("Error loading transferable data for identifier \(identifier): \(error)")
                }
            }
            
            // 切换回主线程更新 UI 和触发弹窗
            await MainActor.run {
                self.photos.insert(contentsOf: newPhotos, at: 0)
                self.selectedItems = [] // 清空 PhotosPicker 的选择
                self.isLoading = false
                loadPhotos() // 刷新照片列表和相册计数, 这会触发预加载

                if !importedIdentifiersSuccess.isEmpty {
                    // 保存成功导入的标识符到 State 变量
                    self.successfullyImportedIdentifiers = importedIdentifiersSuccess
                    // 显示删除确认弹窗
                    self.showDeleteFromLibraryAlert = true
                    appLog("Import complete. Prompting user to delete \(importedIdentifiersSuccess.count) photos from library.")
                } else {
                    appLog("Import process finished, but no photos were successfully imported and saved.")
                     // 可以选择显示一个提示告知用户导入失败
                     self.deleteAlertMessage = "照片导入失败，请重试。"
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

    // 导航栏左侧按钮 (取消选择)
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

    // 进入选择模式
    private func enterSelectionMode() {
        isSelectionMode = true
        selectedPhotoIDs.removeAll() // 清空之前的选择
    }

    // 退出选择模式
    private func exitSelectionMode() {
        isSelectionMode = false
        selectedPhotoIDs.removeAll()
    }

    // 新增：添加缺失的函数定义 (空实现)
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

// 照片详情视图
struct ImageDetailView: View {
    let currentPhoto: Photo
    let photoIndex: Int
    let allPhotos: [Photo]
    let onDelete: (Photo) -> Void
    
    // MARK: - State & Environment
    @Environment(\.presentationMode) var presentationMode
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var showingDeleteAlert = false
    @State private var showingControls = true
    @State private var viewHasAppeared = false
    @State private var renderCount = 0 // Keep for potential debug/unique IDs
    @State private var currentIndex: Int
    @State private var draggingOffset: CGFloat = 0 // Maybe related to dismissal gesture, keep for now
    
    // MARK: - Image Cache
    // Use a simple dictionary cache for this example. NSCache is better for memory management.
    // @State private var imageCache = NSCache<UUID, UIImage>() // Correct way with NSCache
    @StateObject private var imageCacheWrapper = ImageCacheWrapper() // Wrap NSCache in ObservableObject
    @ObservedObject var thumbnailCacheManager: ThumbnailCacheManager // Receive the thumbnail cache manager

    init(currentPhoto: Photo, photoIndex: Int, allPhotos: [Photo], onDelete: @escaping (Photo) -> Void, thumbnailCacheManager: ThumbnailCacheManager) {
        self.currentPhoto = currentPhoto
        self.photoIndex = photoIndex
        self.allPhotos = allPhotos
        self.onDelete = onDelete
        self._currentIndex = State(initialValue: photoIndex)
        self.thumbnailCacheManager = thumbnailCacheManager // Store thumbnail manager
        // imageCache.countLimit = 10 // Example: Limit cache size
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if scale <= 1.0 {
                    TabView(selection: $currentIndex) {
                        ForEach(0..<allPhotos.count, id: \.self) { index in
                            SingleImageView(
                                photo: allPhotos[index],
                                scale: index == currentIndex ? $scale : .constant(1.0),
                                offset: index == currentIndex ? $offset : .constant(.zero),
                                lastScale: $lastScale,
                                lastOffset: $lastOffset,
                                isCurrentView: index == currentIndex,
                                imageCache: imageCacheWrapper.cache, // Pass the full image cache down
                                thumbnailCacheManager: thumbnailCacheManager // Pass the thumbnail cache manager
                            )
                            .tag(index)
                            .id("tabview-item-\(index)-\(renderCount)")
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .id("tab-view-\(currentIndex)-\(renderCount)")
                    .onChange(of: currentIndex) { newIndex in
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                        renderCount += 1
                        appLog("切换到图片 \(allPhotos[newIndex].fileName)")
                        DispatchQueue.global(qos: .userInitiated).async {
                            _ = PhotoManager.shared.loadFullImage(for: allPhotos[newIndex])
                        }
                    }
                } else {
                    SingleImageView(
                        photo: allPhotos[currentIndex],
                        scale: $scale,
                        offset: $offset,
                        lastScale: $lastScale,
                        lastOffset: $lastOffset,
                        isCurrentView: true,
                        imageCache: imageCacheWrapper.cache, // Pass the full image cache down
                        thumbnailCacheManager: thumbnailCacheManager // Pass the thumbnail cache manager
                    )
                    .id("zoomed-view-\(currentIndex)-\(renderCount)")
                }
                
                // 控制栏
                if showingControls {
                    VStack {
                        HStack {
                            Button(action: {
                                appLog("关闭按钮被点击")
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(.leading, 16)
                            
                            Spacer()
                            
                            Button(action: {
                                shareImage()
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            
                            Button(action: {
                                showingDeleteAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 16)
                        }
                        .padding(.top, getSafeAreaTop())
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            ForEach(0..<min(allPhotos.count, 9), id: \.self) { i in
                                Circle()
                                    .fill(i == currentIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                            
                            if allPhotos.count > 9 {
                                Text("+\(allPhotos.count - 9)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .gesture(scale > 1.0 ? nil : TapGesture().onEnded {
                withAnimation {
                    showingControls.toggle()
                }
            })
            .addSwipeGesture(
                onSwipeLeft: {
                    if scale <= 1.0 && currentIndex < allPhotos.count - 1 {
                        withAnimation {
                            currentIndex += 1
                        }
                    }
                },
                onSwipeRight: {
                    if scale <= 1.0 && currentIndex > 0 {
                        withAnimation {
                            currentIndex -= 1
                        }
                    }
                }
            )
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("删除照片"),
                message: Text("确定要删除此照片吗？此操作不可恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    let photoToDelete = allPhotos[currentIndex]
                    onDelete(photoToDelete)
                    if allPhotos.count <= 1 {
                        presentationMode.wrappedValue.dismiss()
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            appLog("ImageDetailView生命周期 - onAppear - 开始")
        }
        .task {
            appLog("ImageDetailView开始task预加载相邻图片")
            preloadAdjacentImages()
        }
    }
    
    private func preloadAdjacentImages() {
        let current = currentIndex
        let total = allPhotos.count
        // Define the preloading window (e.g., 2 images before and after)
        let preloadWindow = 2
        let rangeStart = max(0, current - preloadWindow)
        let rangeEnd = min(total - 1, current + preloadWindow)

        appLog("Preloading images for indices \(rangeStart)...\(rangeEnd)")

        for index in rangeStart...rangeEnd {
            if index == current { continue } // Skip current image
            
            let photoToPreload = allPhotos[index]
            let photoId = photoToPreload.id
            
            // Check cache first
            if imageCacheWrapper.cache.object(forKey: photoId as NSUUID) == nil {
                 appLog("Preloading: Cache miss for \(photoToPreload.fileName) at index \(index). Starting background load.")
                 // Start background task to load and cache
                 Task.detached(priority: .utility) {
                     let loadedImage = PhotoManager.shared.loadFullImage(for: photoToPreload)
                     if let image = loadedImage {
                         // Store in cache on main thread or ensure NSCache is thread-safe (it is)
                          // await MainActor.run { // Not strictly necessary for NSCache set
                         imageCacheWrapper.cache.setObject(image, forKey: photoId as NSUUID)
                         appLog("Preloading: Successfully loaded and cached \(photoToPreload.fileName)")
                          // }
                     } else {
                         appLog("Preloading: Failed to load \(photoToPreload.fileName)")
                     }
                 }
            } else {
                 appLog("Preloading: Cache hit for \(photoToPreload.fileName) at index \(index). No load needed.")
            }
        }
    }
    
    private func shareImage() {
        let photo = allPhotos[currentIndex]
        let imageToShare: UIImage?
        if let loadedImage = PhotoManager.shared.loadFullImage(for: photo) {
            imageToShare = loadedImage
            appLog("shareImage: Using loaded full image for \(photo.fileName)")
        } else {
            // Attempt to load the thumbnail as a fallback
            appLog("shareImage: Failed to load full image for \(photo.fileName), attempting to load thumbnail.")
            imageToShare = PhotoManager.shared.getThumbnail(for: photo)
            if imageToShare == nil {
                 appLog("shareImage: Failed to load thumbnail as well for \(photo.fileName). Sharing will likely fail or use no image.")
            }
        }
        
        // Only proceed if we have an image
        guard let finalImageToShare = imageToShare else {
             appLog("shareImage: No image available to share for \(photo.fileName).")
             // Optionally show an alert to the user
             return
        }
        
        let activityVC = UIActivityViewController(activityItems: [finalImageToShare], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            activityVC.popoverPresentationController?.sourceView = window
            // Set sourceRect to avoid crashes on iPad
             activityVC.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0) 
             activityVC.popoverPresentationController?.permittedArrowDirections = [] // No arrow for centered popover

            rootViewController.present(activityVC, animated: true)
            appLog("shareImage: Presented activity view controller for \(photo.fileName)")
        } else {
             appLog("shareImage: Could not find root view controller to present share sheet.")
        }
    }
    
    private func getSafeAreaTop() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 16
    }
}

// Wrapper for NSCache to use with @StateObject
class ImageCacheWrapper: ObservableObject {
    let cache = NSCache<NSUUID, UIImage>()
    init() {
        // Configure cache limits (Significantly Reduced for Full Images)
        cache.countLimit = 5 // Keep only a few full-res decoded images
        cache.totalCostLimit = 1024 * 1024 * 80 // Limit full image memory cache to ~80MB (adjust based on typical image size)
        appLog("ImageCacheWrapper initialized. Count limit: \(cache.countLimit), Cost limit: \(cache.totalCostLimit)")
    }
}

// 单张图片视图组件
struct SingleImageView: View {
    let photo: Photo
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastScale: CGFloat
    @Binding var lastOffset: CGSize
    let isCurrentView: Bool
    let imageCache: NSCache<NSUUID, UIImage> // Receive the **full image** cache
    @ObservedObject var thumbnailCacheManager: ThumbnailCacheManager // Receive the thumbnail cache manager

    @State private var fullImage: UIImage? = nil
    @State private var thumbnailImage: UIImage? = nil // State for thumbnail
    @State private var isLoading: Bool = false
    @State private var loadTaskId: UUID? = nil // Track the loading task

    // Removed renderCount as it might not be needed with caching
    
    init(photo: Photo, scale: Binding<CGFloat>, offset: Binding<CGSize>, lastScale: Binding<CGFloat>, lastOffset: Binding<CGSize>, isCurrentView: Bool, imageCache: NSCache<NSUUID, UIImage>, thumbnailCacheManager: ThumbnailCacheManager) {
        self.photo = photo
        self._scale = scale
        self._offset = offset
        self._lastScale = lastScale
        self._lastOffset = lastOffset
        self.isCurrentView = isCurrentView
        self.imageCache = imageCache
        self.thumbnailCacheManager = thumbnailCacheManager // Store thumbnail manager

        // Initialize with cached full image if available
        self._fullImage = State(initialValue: imageCache.object(forKey: photo.id as NSUUID))

        // Initialize with thumbnail from thumbnail cache manager (synchronous check)
        self._thumbnailImage = State(initialValue: thumbnailCacheManager.memoryCache.object(forKey: photo.id as NSUUID))

        appLog("SingleImageView init: \(photo.fileName), isCurrent: \(isCurrentView), fullImage cached: \(self.fullImage != nil), thumbnail cached: \(self.thumbnailImage != nil)")

        // If thumbnail wasn't in memory cache, try fetching it (covers disk cache or generation)
        if self.thumbnailImage == nil {
            // Set loading true only if full image also isn't available
            if self.fullImage == nil {
                 self._isLoading = State(initialValue: true) 
            }
            fetchThumbnailIfNeeded()
        }
    }
    
    var body: some View {
        let _ = appLog("SingleImageView body: \(photo.fileName), isCurrent: \(isCurrentView), fullImage is nil: \(fullImage == nil), thumbnail is nil: \(thumbnailImage == nil), isLoading: \(isLoading)")

        return ZStack {
             // Determine which image to display
             let imageToShow: UIImage? = fullImage ?? thumbnailImage
             
             if let displayImage = imageToShow {
                  Image(uiImage: displayImage)
                      .resizable()
                      .interpolation(fullImage != nil ? .high : .medium) // Use high quality only for full image
                      .scaledToFit()
                      .clipped()
                      .scaleEffect(scale)
                      .offset(offset)
                      .id("image-\(photo.id)-\(fullImage != nil ? "full" : "thumb")") // More stable ID
                      .simultaneousGesture(isCurrentView ? doubleTapGesture : nil)
                      .simultaneousGesture(isCurrentView ? magnificationGesture : nil)
                      .simultaneousGesture(isCurrentView && scale > 1.0 ? dragGesture : nil, including: scale > 1.0 ? .all : .subviews)
             } else {
                  // Fallback placeholder if even thumbnail isn't available
                  Rectangle()
                      .fill(Color.secondary.opacity(0.2))
                      .id("placeholder-\(photo.id)")
             }
            
             // Show progress only if loading is active AND *neither* full image nor thumbnail is loaded yet
             if isLoading && fullImage == nil && thumbnailImage == nil {
                 ProgressView()
                     .scaleEffect(1.5)
                     // .foregroundColor(.white) // Adjust color if needed based on background
             }
        }
        .task(id: photo.id) { // Task tied to photo.id
            appLog("SingleImageView .task: \(photo.fileName), isCurrent: \(isCurrentView) - Task started")
            // Only load if it's the current view and the full image hasn't been loaded yet
            if isCurrentView && fullImage == nil {
                appLog("SingleImageView .task: \(photo.fileName) - Condition met (current, no full img), calling loadFullSizeImage")
                await loadFullSizeImage()
            } else {
                 appLog("SingleImageView .task: \(photo.fileName) - Condition NOT met (isCurrent: \(isCurrentView), fullImage cached/loaded: \(fullImage != nil))")
            }
        }
        .onChange(of: isCurrentView) { becameCurrent in
            appLog("SingleImageView onChange(isCurrentView): \(photo.fileName), becameCurrent: \(becameCurrent), fullImage is nil: \(fullImage == nil)")
            if becameCurrent && fullImage == nil {
                Task {
                    appLog("SingleImageView onChange(isCurrentView): \(photo.fileName) - Condition met, calling loadFullSizeImage")
                    await loadFullSizeImage()
                    appLog("SingleImageView onChange(isCurrentView): \(photo.fileName) - loadFullSizeImage returned")
                }
            } else if !becameCurrent {
                 // Optional: Cancel loading task if view is no longer current?
                 // Requires managing the Task handle. For now, let preloading handle this.
            }
        }
        .onAppear { // Also try loading on appear if needed
             appLog("SingleImageView onAppear: \(photo.fileName), isCurrent: \(isCurrentView), fullImage is nil: \(fullImage == nil)")
             if isCurrentView && fullImage == nil && !isLoading {
                 // Attempt load full image if it appears as current and isn't already loaded/loading
                 Task {
                     await loadFullSizeImage()
                 }
             }
             // Ensure thumbnail is loaded if somehow missed during init
             if thumbnailImage == nil {
                 fetchThumbnailIfNeeded()
                 // Logging now happens inside fetchThumbnailIfNeeded
             }
        }
    }
    
    private func loadFullSizeImage() async {
        // Avoid starting a new load if one is already in progress for this image instance
         guard loadTaskId == nil else {
             appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Load already in progress (task \(loadTaskId!)). Skipping.")
             return
         }
         
         // Check cache again just before loading (might have been populated by preloading)
         if let cachedImage = imageCache.object(forKey: photo.id as NSUUID) {
             if self.fullImage == nil { // Only update if not already set
                 await MainActor.run {
                      appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Found in cache just before loading. Setting fullImage.")
                      self.fullImage = cachedImage
                      self.isLoading = false // Ensure loading indicator is off
                 }
             } else {
                  appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Found in cache, but fullImage already set. No state change needed.")
             }
             return // Don't proceed to load from disk
         }
         
         let taskId = UUID()
         loadTaskId = taskId
         
         await MainActor.run {
             appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Cache miss. Setting isLoading = true. Task ID: \(taskId)")
             self.isLoading = true
         }
        
        appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Starting Task.detached for PhotoManager")
        
        let loadedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            appLog("SingleImageView loadFullSizeImage (Task.detached): \(photo.fileName) - Calling PhotoManager.loadFullImage")
            let result = PhotoManager.shared.loadFullImage(for: photo)
            appLog("SingleImageView loadFullSizeImage (Task.detached): \(photo.fileName) - PhotoManager.loadFullImage returned \(result == nil ? "nil" : "image")")
            return result
        }.value
        
        // Check if the task is still the current one before updating state
         guard loadTaskId == taskId else {
             appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Task \(taskId) is stale (current task is \(loadTaskId?.uuidString ?? "nil")). Discarding result.")
             // Don't update state if a newer task has started (e.g., view re-appeared)
             return
         }
        
        appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Task \(taskId) finished, preparing MainActor update")
        
        await MainActor.run {
            appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - Updating state for task \(taskId)")
            if let image = loadedImage {
                appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - Success, setting fullImage and caching.")
                self.fullImage = image
                self.isLoading = false // Turn off loading indicator upon success
                // Cache the loaded image
                imageCache.setObject(image, forKey: photo.id as NSUUID)
                 // Consider cost if using totalCostLimit in NSCache
                 // imageCache.setObject(image, forKey: photo.id as NSUUID, cost: image.diskSize) // Need a way to estimate cost
            } else {
                appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - Failed to load image")
                // Keep showing thumbnail or placeholder
                // If full image fails, ensure loading indicator is off ONLY if thumbnail is available
                if self.thumbnailImage != nil { 
                     self.isLoading = false
                }
            }
            self.loadTaskId = nil // Clear task ID after completion/failure
            appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - State update complete, fullImage is nil: \(self.fullImage == nil), isLoading: \(self.isLoading)")
        }
    }
    
    // 手势定义
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                // 限制缩放范围
                let newScale = scale * delta
                scale = min(max(newScale, 0.8), 5) // 允许缩小一点
            }
            .onEnded { _ in
                lastScale = 1.0
                // 如果缩放小于1，弹回1
                if scale < 1.0 {
                    withAnimation {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width / scale, // 根据缩放调整拖动
                        height: lastOffset.height + value.translation.height / scale
                    )
                }
            }
            .onEnded { value in
                lastOffset = offset
                // 添加边界检查，防止图片拖出屏幕太多 (可选)
                // ... 边界检查逻辑 ...
            }
    }
    
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { 
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        // 双击放大到固定倍数或适应屏幕
                        scale = 2.5 
                    }
                }
            }
    }

    // Helper function to fetch thumbnail using the manager
    private func fetchThumbnailIfNeeded() {
        guard thumbnailImage == nil else { return } // Don't fetch if already loaded
        
        // Set isLoading if fullImage is also nil
        if fullImage == nil && !isLoading {
            isLoading = true
        }
        
        let photoID = photo.id // Capture photo ID for logging
        appLog("SingleImageView fetchThumbnailIfNeeded: Requesting thumbnail for \(photoID) from manager")
        
        // Remove capture list for struct self. Closure captures a copy.
        thumbnailCacheManager.getThumbnail(for: photo) { image in 
            // Updates will be applied to the view's state if it still exists.
            Task { @MainActor in
                if let img = image {
                    // Check again in case it was loaded by another means concurrently
                    // Accessing self.thumbnailImage here refers to the state associated with this view instance.
                    if self.thumbnailImage == nil { 
                        self.thumbnailImage = img
                        appLog("SingleImageView fetchThumbnailIfNeeded: Thumbnail loaded for \(photoID)")
                    }
                    // Turn off loading indicator once thumbnail is available, even if full isn't yet
                    self.isLoading = false 
                } else {
                    appLog("SingleImageView fetchThumbnailIfNeeded: Failed to load thumbnail for \(photoID)")
                    // If thumbnail fails, stop the loading indicator for now.
                    // If full image load also fails later, it might remain blank, which is acceptable.
                    self.isLoading = false 
                }
            }
        }
    }
}

// 添加修复SwiftUI的TabView手势冲突的扩展
extension View {
    func addSwipeGesture(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) -> some View {
        self.gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    let verticalAmount = value.translation.height
                    
                    if abs(horizontalAmount) > abs(verticalAmount) {
                        if horizontalAmount < 0 {
                            onSwipeLeft()
                        } else {
                            onSwipeRight()
                        }
                    }
                }
        )
    }
}

