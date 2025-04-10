import Foundation
import UIKit
import Photos
import ImageIO
import CoreGraphics

// 照片模型
struct Photo: Identifiable {
    let id: UUID
    let albumId: UUID
    let fileName: String
    let createdAt: Date
    var thumbnailImage: UIImage
    
    // 完整的图片路径
    var imagePath: URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let albumDirectory = documentsDirectory.appendingPathComponent("albums/\(albumId.uuidString)")
        return albumDirectory.appendingPathComponent(fileName)
    }
    
    // 默认构造器 - 使用占位图
    init(albumId: UUID, fileName: String, createdAt: Date, thumbnailImage: UIImage?) {
        self.id = UUID() // 这里生成一个新的UUID
        self.albumId = albumId
        self.fileName = fileName
        self.createdAt = createdAt
        // 确保总是有一个缩略图
        self.thumbnailImage = thumbnailImage ?? UIImage(systemName: "photo")!
    }
}

class PhotoManager {
    static let shared = PhotoManager()
    
    // 图片缓存
    private let imageCache = NSCache<NSString, UIImage>()
    
    private init() {
        createAlbumDirectoriesIfNeeded()
        
        // 配置图片缓存
        imageCache.countLimit = 100
    }
    
    // 创建相册目录
    private func createAlbumDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let albumsDirectory = documentsDirectory.appendingPathComponent("albums")
        
        if !fileManager.fileExists(atPath: albumsDirectory.path) {
            do {
                try fileManager.createDirectory(at: albumsDirectory, withIntermediateDirectories: true)
            } catch {
                print("创建相册目录失败: \(error)")
            }
        }
    }
    
    // 获取或创建相册目录
    private func getAlbumDirectory(for albumId: UUID) -> URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let albumDirectory = documentsDirectory.appendingPathComponent("albums/\(albumId.uuidString)")
        
        if !fileManager.fileExists(atPath: albumDirectory.path) {
            do {
                try fileManager.createDirectory(at: albumDirectory, withIntermediateDirectories: true)
                return albumDirectory
            } catch {
                print("创建相册目录失败: \(error)")
                return nil
            }
        }
        
        return albumDirectory
    }
    
    // 保存照片到相册
    func savePhoto(image: UIImage, toAlbum albumId: UUID) -> Photo? {
        print("开始保存照片到相册: \(albumId)")
        
        guard let albumDirectory = getAlbumDirectory(for: albumId) else {
            print("无法获取相册目录")
            return nil
        }
        
        // 生成文件名
        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = albumDirectory.appendingPathComponent(fileName)
        
        print("保存照片到路径: \(fileURL.path)")
        
        // 创建高质量缩略图
        let thumbnailSize = CGSize(width: 300, height: 300)
        let thumbnailImage = createHighQualityThumbnail(for: image, size: thumbnailSize) ?? UIImage(systemName: "photo")!
        
        // 保存原图 - 确保使用最高质量
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            print("转换图片为JPEG数据失败")
            return nil
        }
        
        print("图片数据大小: \(imageData.count) bytes")
        
        do {
            try imageData.write(to: fileURL)
            
            // 验证文件是否成功写入
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: fileURL.path) {
                // 检查写入的文件大小
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? UInt64 {
                    print("文件成功写入，大小: \(fileSize) bytes")
                    
                    if fileSize == 0 {
                        print("警告：写入的文件大小为0")
                    }
                }
            } else {
                print("警告：文件似乎未成功写入")
            }
            
            // 创建照片模型
            let photo = Photo(
                albumId: albumId,
                fileName: fileName,
                createdAt: Date(),
                thumbnailImage: thumbnailImage
            )
            
            // 更新相册照片数量
            updateAlbumPhotoCount(albumId: albumId)
            
            print("照片保存成功: \(fileName)")
            return photo
        } catch {
            print("保存照片失败: \(error)")
            return nil
        }
    }
    
    // 创建高质量缩略图
    private func createHighQualityThumbnail(for image: UIImage, size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0 // 使用2倍屏幕比例
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        
        return renderer.image { context in
            // 计算缩放和裁剪以保持宽高比
            let aspectRatio = image.size.width / image.size.height
            let thumbnailAspectRatio = size.width / size.height
            
            var drawRect = CGRect(origin: .zero, size: size)
            
            if aspectRatio > thumbnailAspectRatio {
                // 图片更宽，需要裁剪宽度
                let newWidth = size.height * aspectRatio
                drawRect.origin.x = -(newWidth - size.width) / 2
                drawRect.size.width = newWidth
            } else {
                // 图片更高，需要裁剪高度
                let newHeight = size.width / aspectRatio
                drawRect.origin.y = -(newHeight - size.height) / 2
                drawRect.size.height = newHeight
            }
            
            image.draw(in: drawRect)
        }
    }
    
    // 更新相册照片数量
    private func updateAlbumPhotoCount(albumId: UUID) {
        // 获取相册的所有照片
        let photos = getPhotos(fromAlbum: albumId)
        
        // 从数据库获取相册
        if let albums = try? DatabaseManager.shared.getAllAlbums().filter({ $0.id == albumId }),
           let album = albums.first {
            
            // 更新相册照片数量
            let updatedAlbum = Album(
                id: album.id,
                name: album.name,
                coverImage: album.coverImage,
                count: photos.count + 1, // +1 是因为我们刚刚添加了一张新照片
                createdAt: album.createdAt
            )
            
            // 更新数据库
            _ = DatabaseManager.shared.updateAlbum(updatedAlbum)
        }
    }
    
    // 获取相册中的所有照片
    func getPhotos(fromAlbum albumId: UUID) -> [Photo] {
        let fileManager = FileManager.default
        guard let albumDirectory = getAlbumDirectory(for: albumId) else {
            return []
        }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: albumDirectory, includingPropertiesForKeys: nil)
            let photoFiles = fileURLs.filter { $0.pathExtension.lowercased() == "jpg" }
            
            var photos: [Photo] = []
            
            for fileURL in photoFiles {
                let fileName = fileURL.lastPathComponent
                
                // 加载缩略图 - 使用高质量方法
                if let imageData = try? Data(contentsOf: fileURL),
                   let image = UIImage(data: imageData) {
                    let thumbnailSize = CGSize(width: 300, height: 300)
                    let thumbnailImage = createHighQualityThumbnail(for: image, size: thumbnailSize)
                    
                    let photo = Photo(
                        albumId: albumId,
                        fileName: fileName,
                        createdAt: (try? fileManager.attributesOfItem(atPath: fileURL.path)[.creationDate] as? Date) ?? Date(),
                        thumbnailImage: thumbnailImage
                    )
                    
                    photos.append(photo)
                }
            }
            
            // 按创建日期排序
            return photos.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("获取相册照片失败: \(error)")
            return []
        }
    }
    
    // 删除照片
    func deletePhoto(_ photo: Photo) -> Bool {
        guard let imagePath = photo.imagePath else {
            return false
        }
        
        let fileManager = FileManager.default
        
        do {
            try fileManager.removeItem(at: imagePath)
            
            // 更新相册照片数量
            updateAlbumPhotoCount(albumId: photo.albumId)
            
            return true
        } catch {
            print("删除照片失败: \(error)")
            return false
        }
    }
    
    // 加载原始图片 - 修复图片加载黑屏问题
    func loadFullImage(for photo: Photo) -> UIImage? {
        appLog("开始加载图片: \(photo.fileName)")
        
        // 首先检查是否已有缩略图，如果有则可以临时返回
        let thumbnailImage = photo.thumbnailImage
        
        guard let imagePath = photo.imagePath else {
            appLog("无法获取图片路径")
            return thumbnailImage
        }
        
        appLog("图片路径: \(imagePath.path)")
        
        // 使用图片缓存以提高性能
        let filePathString = imagePath.path
        let cacheKey = NSString(string: filePathString)
        
        // 检查缓存中是否有图片
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            appLog("从缓存加载图片成功")
            return cachedImage
        }
        
        appLog("缓存未命中，尝试从文件加载: \(filePathString)")
        
        // 检查文件是否存在
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: imagePath.path) else {
            // 修改：添加更明确的日志
            appLog("错误：文件不存在于路径: \(imagePath.path)")
            return thumbnailImage // 或者返回 nil，根据业务逻辑决定
        }
        
        appLog("文件确认存在: \(imagePath.path)")
        
        var fileSize: UInt64 = 0
        do {
            let attr = try fileManager.attributesOfItem(atPath: imagePath.path)
            fileSize = attr[FileAttributeKey.size] as? UInt64 ?? 0
            appLog("文件大小: \(fileSize) bytes")
            
            if fileSize == 0 {
                appLog("文件大小为0，返回缩略图")
                return thumbnailImage
            }
        } catch {
            appLog("获取文件属性失败: \(error)")
        }
        
        do {
            // 读取图片数据
            appLog("尝试读取文件数据: \(imagePath.path)")
            let data = try Data(contentsOf: imagePath, options: .mappedIfSafe)
            appLog("成功读取图片数据，大小: \(data.count) bytes")
            
            if data.isEmpty {
                appLog("错误：读取到的图片数据为空")
                return thumbnailImage
            }
            
            // 使用UIImage初始化
            appLog("尝试使用 UIImage(data:) 初始化")
            if let image = UIImage(data: data) {
                appLog("使用UIImage(data:)加载成功")
                
                // 验证图片是否有效
                if image.size.width > 0 && image.size.height > 0 {
                    appLog("图片尺寸有效: \(image.size.width) x \(image.size.height)")
                    
                    // 保存到缓存
                    imageCache.setObject(image, forKey: cacheKey)
                    return image
                } else {
                    appLog("图片尺寸无效")
                }
            }
            
            // 尝试使用ImageIO框架作为备选方案
            appLog("尝试使用 ImageIO 初始化")
            var options: [CFString: Any] = [:]
            options[kCGImageSourceShouldCache] = true
            options[kCGImageSourceCreateThumbnailWithTransform] = true
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            
            appLog("ImageIO: 尝试创建 CGImageSource")
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                appLog("错误：无法创建图片源 (CGImageSourceCreateWithData 返回 nil)")
                return thumbnailImage
            }
            
            let count = CGImageSourceGetCount(imageSource)
            appLog("图片源中的图片数量: \(count)")
            
            if count == 0 {
                appLog("图片源中没有图片")
                return thumbnailImage
            }
            
            appLog("ImageIO: 尝试创建 CGImageAtIndex")
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, options as CFDictionary) else {
                appLog("错误：无法创建CGImage (CGImageSourceCreateImageAtIndex 返回 nil)")
                return thumbnailImage
            }
            
            appLog("ImageIO: 成功创建 CGImage")
            let fullImage = UIImage(cgImage: cgImage)
            appLog("使用CGImage加载成功，尺寸: \(fullImage.size.width) x \(fullImage.size.height)")
            
            // 保存到缓存
            imageCache.setObject(fullImage, forKey: cacheKey)
            
            return fullImage
        } catch {
            // 修改：记录详细错误
            appLog("错误：加载原图失败，文件路径: \(imagePath.path), 错误描述: \(error)")
            return thumbnailImage
        }
    }
    
    // 强制预加载缩略图 - 确保缩略图已经加载
    func ensureThumbnailLoaded(for photo: Photo) -> Photo {
        if photo.thumbnailImage != UIImage(systemName: "photo")! {
            return photo
        }
        
        appLog("缩略图不存在，尝试重新生成：\(photo.fileName)")
        
        guard let imagePath = photo.imagePath else {
            appLog("无法获取图片路径")
            return photo
        }
        
        do {
            let data = try Data(contentsOf: imagePath)
            if let image = UIImage(data: data) {
                let thumbnailSize = CGSize(width: 300, height: 300)
                if let thumbnailImage = createHighQualityThumbnail(for: image, size: thumbnailSize) {
                    var updatedPhoto = photo
                    updatedPhoto.thumbnailImage = thumbnailImage
                    appLog("成功重新生成缩略图")
                    return updatedPhoto
                }
            }
        } catch {
            appLog("重新生成缩略图失败: \(error)")
        }
        
        return photo
    }
} 