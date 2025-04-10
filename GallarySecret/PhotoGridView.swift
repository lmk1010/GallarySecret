import SwiftUI
import PhotosUI

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
    
    init(album: Album) {
        self.album = album
        _updatedAlbum = State(initialValue: album)
    }
    
    var body: some View {
        ZStack {
            contentView
            loadingView
        }
        .navigationTitle(updatedAlbum.name)
        .navigationBarItems(trailing: trailingButtons)
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
                    }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                preloadThumbnails()
            }
        }
    }
    
    // 预加载所有缩略图
    private func preloadThumbnails() {
        guard !preloadedThumbnails && !photos.isEmpty else {
            return
        }
        
        appLog("开始预加载缩略图")
        
        // 预加载第一张照片的原图
        if let firstPhoto = photos.first {
            DispatchQueue.global(qos: .utility).async {
                appLog("预加载第一张照片的原图: \(firstPhoto.fileName)")
                _ = PhotoManager.shared.loadFullImage(for: firstPhoto)
                appLog("第一张照片预加载完成")
            }
        }
        
        // 标记为已预加载
        preloadedThumbnails = true
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
                    Button(action: {
                        appLog("用户点击缩略图: \(photo.fileName)")
                        
                        selectedPhoto = photo
                        appLog("Button Action: Set selectedPhoto to \(photo.fileName) to trigger cover")
                    }) {
                        photoThumbnailView(for: photo)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            deletePhoto(photo)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(8)
        }
    }
    
    // 照片缩略图视图
    private func photoThumbnailView(for photo: Photo) -> some View {
        ZStack {
            Image(uiImage: photo.thumbnailImage)
                .interpolation(.high)
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width / 4 - 10, height: UIScreen.main.bounds.width / 4 - 10)
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .clipped() // 确保图片不超出边界
        }
    }
    
    // 顶部按钮
    private var trailingButtons: some View {
        HStack {
            // 相册选择器
            PhotosPicker(
                selection: $selectedItems,
                matching: .images,
                photoLibrary: .shared()) {
                    Image(systemName: "plus")
                }
                .onChange(of: selectedItems) { newItems in
                    importPhotos(from: newItems)
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
        
        Task {
            var newPhotos: [Photo] = []
            
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    if let photo = PhotoManager.shared.savePhoto(image: image, toAlbum: album.id) {
                        newPhotos.append(photo)
                    }
                }
            }
            
            DispatchQueue.main.async {
                // 更新UI
                self.photos.insert(contentsOf: newPhotos, at: 0)
                self.selectedItems = []
                self.isLoading = false
                
                // 更新相册信息
                loadPhotos()
            }
        }
    }
    
    // 删除照片
    private func deletePhoto(_ photo: Photo) {
        if PhotoManager.shared.deletePhoto(photo) {
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                photos.remove(at: index)
                if selectedPhoto?.id == photo.id {
                    selectedPhoto = nil
                }
                loadPhotos()
            }
        }
    }
    
    // 获取顶部安全区域高度
    private func getSafeAreaTop() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 16
    }
}

// 照片详情视图
struct ImageDetailView: View {
    let currentPhoto: Photo
    let photoIndex: Int
    let allPhotos: [Photo]
    let onDelete: (Photo) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var showingDeleteAlert = false
    @State private var showingControls = true
    @State private var viewHasAppeared = false
    @State private var renderCount = 0
    @State private var currentIndex: Int
    @State private var draggingOffset: CGFloat = 0
    
    init(currentPhoto: Photo, photoIndex: Int, allPhotos: [Photo], onDelete: @escaping (Photo) -> Void) {
        self.currentPhoto = currentPhoto
        self.photoIndex = photoIndex
        self.allPhotos = allPhotos
        self.onDelete = onDelete
        _currentIndex = State(initialValue: photoIndex)
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
                                isCurrentView: index == currentIndex
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
                        isCurrentView: true
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
        let indices = [
            max(0, currentIndex - 1),
            currentIndex,
            min(allPhotos.count - 1, currentIndex + 1)
        ].filter { $0 != currentIndex }
        
        for index in indices {
            DispatchQueue.global(qos: .utility).async {
                appLog("预加载相邻图片: \(allPhotos[index].fileName)")
                _ = PhotoManager.shared.loadFullImage(for: allPhotos[index])
            }
        }
    }
    
    private func shareImage() {
        let photo = allPhotos[currentIndex]
        let imageToShare: UIImage
        if let loadedImage = PhotoManager.shared.loadFullImage(for: photo) {
            imageToShare = loadedImage
        } else {
            imageToShare = photo.thumbnailImage
        }
        let activityVC = UIActivityViewController(activityItems: [imageToShare], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            activityVC.popoverPresentationController?.sourceView = window
            rootViewController.present(activityVC, animated: true)
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

// 单张图片视图组件
struct SingleImageView: View {
    let photo: Photo
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastScale: CGFloat
    @Binding var lastOffset: CGSize
    let isCurrentView: Bool
    
    @State private var fullImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var renderCount = 0
    
    init(photo: Photo, scale: Binding<CGFloat>, offset: Binding<CGSize>, lastScale: Binding<CGFloat>, lastOffset: Binding<CGSize>, isCurrentView: Bool) {
        self.photo = photo
        self._scale = scale
        self._offset = offset
        self._lastScale = lastScale
        self._lastOffset = lastOffset
        self.isCurrentView = isCurrentView
        appLog("SingleImageView init: \(photo.fileName), isCurrent: \(isCurrentView)")
    }
    
    var body: some View {
        // 添加日志：检查 displayImage
        let displayImage = fullImage ?? photo.thumbnailImage
        let _ = appLog("SingleImageView body: \(photo.fileName), isCurrent: \(isCurrentView), fullImage is nil: \(fullImage == nil), displayImage size: \(displayImage.size)")
        
        return ZStack {
            Image(uiImage: displayImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .id("image-\(renderCount)-\(isCurrentView ? "current" : "other")")
                .simultaneousGesture(isCurrentView ? doubleTapGesture : nil)
                .simultaneousGesture(isCurrentView ? magnificationGesture : nil)
                .simultaneousGesture(isCurrentView && scale > 1.0 ? dragGesture : nil, including: scale > 1.0 ? .all : .subviews)
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .foregroundColor(.white)
            }
        }
        .task(id: photo.id) { 
            // 添加日志： .task 开始
            appLog("SingleImageView .task: \(photo.fileName), isCurrent: \(isCurrentView), fullImage is nil: \(fullImage == nil) - Task started")
            
            if isCurrentView && fullImage == nil {
                // 添加日志： 条件满足，准备调用 loadFullSizeImage
                appLog("SingleImageView .task: \(photo.fileName) - Condition met, calling loadFullSizeImage")
                await loadFullSizeImage()
                // 添加日志： loadFullSizeImage 调用完成
                appLog("SingleImageView .task: \(photo.fileName) - loadFullSizeImage returned")
            } else {
                // 添加日志： 条件不满足
                appLog("SingleImageView .task: \(photo.fileName) - Condition NOT met (isCurrent: \(isCurrentView), fullImage is nil: \(fullImage == nil))")
            }
        }
        .onChange(of: isCurrentView) { becameCurrent in
            // 添加日志： isCurrentView 变化
            appLog("SingleImageView onChange(isCurrentView): \(photo.fileName), becameCurrent: \(becameCurrent), fullImage is nil: \(fullImage == nil)")
            if becameCurrent && fullImage == nil {
                Task { 
                    appLog("SingleImageView onChange(isCurrentView): \(photo.fileName) - Condition met, calling loadFullSizeImage")
                    await loadFullSizeImage()
                    appLog("SingleImageView onChange(isCurrentView): \(photo.fileName) - loadFullSizeImage returned")
                }
            }
        }
    }
    
    private func loadFullSizeImage() async {
        // 添加日志： loadFullSizeImage 开始
        appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Function start")
        
        await MainActor.run { 
            if self.fullImage == nil { 
                 appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Setting isLoading = true")
                 self.isLoading = true
                 self.renderCount += 1
            } else {
                 appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - fullImage already exists, not setting isLoading")
            }
        }
        
        appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Starting Task.detached for PhotoManager")
        
        let loadedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            // 添加日志： Task.detached 开始调用 PhotoManager
            appLog("SingleImageView loadFullSizeImage (Task.detached): \(photo.fileName) - Calling PhotoManager.loadFullImage")
            let result = PhotoManager.shared.loadFullImage(for: photo)
            // 添加日志： Task.detached 完成调用 PhotoManager
            appLog("SingleImageView loadFullSizeImage (Task.detached): \(photo.fileName) - PhotoManager.loadFullImage returned \(result == nil ? "nil" : "image")")
            return result
        }.value
        
        appLog("SingleImageView loadFullSizeImage: \(photo.fileName) - Task.detached finished, preparing MainActor update")
        
        await MainActor.run { 
            appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - Updating state")
            if let image = loadedImage {
                appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - Success, setting fullImage")
                self.fullImage = image
            } else {
                appLog("SingleImageView loadFullSizeImage (MainActor): \(photo.fileName) - Failed to load image")
            }
            self.isLoading = false
            self.renderCount += 1
            // 添加日志： 状态更新完成
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

