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
    @State private var showingImageDetail = false
    @State private var selectedPhoto: Photo?
    @State private var preloadedThumbnails = false // 跟踪是否已预加载
    
    init(album: Album) {
        self.album = album
        _updatedAlbum = State(initialValue: album)
    }
    
    var body: some View {
        // 将复杂的 ZStack 拆分为多个视图组件
        ZStack {
            // 内容视图
            contentView
            
            // 加载指示器
            loadingView
        }
        .navigationTitle(updatedAlbum.name)
        .navigationBarItems(trailing: trailingButtons)
        .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        // 使用overlay+sheet代替fullScreenCover
        .sheet(isPresented: $showingImageDetail, onDismiss: {
            appLog("照片详情视图已关闭")
        }) {
            if let photo = selectedPhoto, let index = photos.firstIndex(where: { $0.id == photo.id }) {
                // 使用NavigationView包装以确保模态状态正确
                NavigationView {
                    ImageDetailView(
                        currentPhoto: photo,
                        photoIndex: index,
                        allPhotos: photos,
                        onDelete: { photoToDelete in
                            if let indexToDelete = photos.firstIndex(where: { $0.id == photoToDelete.id }) {
                                photos.remove(at: indexToDelete)
                                loadPhotos()
                            }
                        }
                    )
                    .navigationBarHidden(true)
                    .statusBar(hidden: true)
                    .onAppear {
                        appLog("图片详情页出现 - 从Sheet")
                    }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            appLog("PhotoGridView onAppear - 开始加载照片")
            loadPhotos()
            // 预加载第一张缩略图以避免渲染延迟
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
                        
                        // 先设置选中的照片，然后延迟一点点时间再显示详情视图
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showingImageDetail = true
                        }
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
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    @State private var viewHasAppeared = false
    @State private var renderCount = 0
    @State private var currentIndex: Int
    @State private var draggingOffset: CGFloat = 0
    
    // 添加初始化后启动图片加载
    init(currentPhoto: Photo, photoIndex: Int, allPhotos: [Photo], onDelete: @escaping (Photo) -> Void) {
        self.currentPhoto = currentPhoto
        self.photoIndex = photoIndex
        self.allPhotos = allPhotos
        self.onDelete = onDelete
        _currentIndex = State(initialValue: photoIndex)
        
        // 立即开始加载原图
        appLog("ImageDetailView初始化 - 立即开始加载图片: \(currentPhoto.fileName)")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = PhotoManager.shared.loadFullImage(for: currentPhoto)
        }
    }
    
    var body: some View {
        // 使用更简单直接的结构 - 减少嵌套
        GeometryReader { geometry in
            ZStack {
                // 始终保持黑色背景
                Color.black.edgesIgnoringSafeArea(.all)
                
                if scale <= 1.0 {
                    // 使用TabView实现滑动
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
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .onChange(of: currentIndex) { newIndex in
                        // 切换到新图片时重置状态
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                        appLog("切换到图片 \(allPhotos[newIndex].fileName)")
                        
                        // 预加载当前图片
                        DispatchQueue.global(qos: .userInitiated).async {
                            _ = PhotoManager.shared.loadFullImage(for: allPhotos[newIndex])
                        }
                    }
                } else {
                    // 在缩放模式下直接显示当前图片
                    SingleImageView(
                        photo: allPhotos[currentIndex],
                        scale: $scale,
                        offset: $offset,
                        lastScale: $lastScale,
                        lastOffset: $lastOffset,
                        isCurrentView: true
                    )
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
                        
                        // 添加图片索引指示器
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
                    
                    // 如果这是最后一张图片，关闭视图
                    if allPhotos.count <= 1 {
                        presentationMode.wrappedValue.dismiss()
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            appLog("ImageDetailView生命周期 - onAppear - 开始")
            
            // 立即刷新UI以显示缩略图
            DispatchQueue.main.async {
                renderCount += 1
                viewHasAppeared = true
                appLog("视图已经出现，设置标志")
                
                // 预加载前后图片
                preloadAdjacentImages()
            }
        }
    }
    
    // 预加载相邻图片
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
    
    // 分享图片
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
    
    // 获取顶部安全区域高度
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
    
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    @State private var renderCount = 0
    
    var body: some View {
        ZStack {
            // 显示图片
            let displayImage = fullImage ?? photo.thumbnailImage
            Image(uiImage: displayImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .id("image-\(renderCount)")
                // 组合手势，确保正确的顺序和优先级
                .simultaneousGesture(isCurrentView ? doubleTapGesture : nil)
                .simultaneousGesture(isCurrentView ? magnificationGesture : nil)
                .simultaneousGesture(isCurrentView && scale > 1.0 ? dragGesture : nil, including: scale > 1.0 ? .all : .subviews)
            
            // 加载指示器
            if isLoading && fullImage == nil {
                ProgressView()
                    .scaleEffect(1.5)
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            appLog("单张图片视图出现: \(photo.fileName)")
            loadFullSizeImage()
        }
    }
    
    // 加载全尺寸图片
    private func loadFullSizeImage() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            appLog("加载原图: \(photo.fileName)")
            
            if let image = PhotoManager.shared.loadFullImage(for: photo) {
                DispatchQueue.main.async {
                    appLog("原图加载完成: \(photo.fileName)")
                    self.fullImage = image
                    self.isLoading = false
                    self.renderCount += 1
                }
            } else {
                DispatchQueue.main.async {
                    appLog("原图加载失败: \(photo.fileName)")
                    self.isLoading = false
                }
            }
        }
    }
    
    // 手势定义
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 1), 5)
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                lastOffset = offset
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
                            // 左滑
                            onSwipeLeft()
                        } else {
                            // 右滑
                            onSwipeRight()
                        }
                    }
                }
        )
    }
}

