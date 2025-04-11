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
    // var thumbnailImage: UIImage // 移除，不再直接存储缩略图

    // 完整的图片路径
    var imagePath: URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let albumDirectory = documentsDirectory.appendingPathComponent("albums/\(albumId.uuidString)")
        return albumDirectory.appendingPathComponent(fileName)
    }

    // 默认构造器 - 不再需要 thumbnailImage 参数
    init(id: UUID = UUID(), albumId: UUID, fileName: String, createdAt: Date) {
        self.id = id // 允许传入已存在的 ID
        self.albumId = albumId
        self.fileName = fileName
        self.createdAt = createdAt
    }
}

class PhotoManager {
    static let shared = PhotoManager()

    // 图片缓存 (用于缩略图)
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        createAlbumDirectoriesIfNeeded()

        // 配置图片缓存
        imageCache.countLimit = 200 // 可以适当增加缓存数量
        imageCache.totalCostLimit = 1024 * 1024 * 100 // 限制缓存大小为 100MB (粗略估计)
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
                 appLog("创建相册根目录失败: \(error)") // 使用 appLog
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
                 appLog("创建相册目录失败: \(albumId), error: \(error)") // 使用 appLog
                return nil
            }
        }

        return albumDirectory
    }

    // 保存照片到相册 (返回 Photo 元数据，预缓存缩略图)
    func savePhoto(image: UIImage, toAlbum albumId: UUID) -> Photo? {
         appLog("PhotoManager: 开始保存照片到相册: \(albumId)") // 添加日志标识

        guard let albumDirectory = getAlbumDirectory(for: albumId) else {
             appLog("PhotoManager: 无法获取相册目录")
            return nil
        }

        // 使用 UUID 作为文件名
        let photoId = UUID()
        let fileName = "\(photoId.uuidString).jpg"
        let fileURL = albumDirectory.appendingPathComponent(fileName)

         appLog("PhotoManager: 保存照片到路径: \(fileURL.path)")

        // 创建高质量缩略图
        let thumbnailSize = CGSize(width: 300, height: 300) // 标准缩略图尺寸
        guard let thumbnailImage = createHighQualityThumbnail(for: image, size: thumbnailSize) else {
             appLog("PhotoManager: 创建缩略图失败")
             return nil // 创建缩略图失败则不保存
        }

        // 保存原图 - 使用后台队列避免阻塞
        // 使用 1.0 保证质量，但对于非常大的图片可能需要考虑压缩
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
             appLog("PhotoManager: 转换图片为JPEG数据失败")
            return nil
        }

         appLog("PhotoManager: 图片数据大小: \(imageData.count) bytes")

        do {
            // 在后台线程写入文件，避免阻塞主线程 (如果图片很大)
            // 注意：这里简化处理，实际可能需要更复杂的队列管理
             try imageData.write(to: fileURL, options: .atomic) // 使用 atomic 保证写入完整性

            // 验证文件是否成功写入... (可以按需添加)
             appLog("PhotoManager: 文件成功写入: \(fileName)")

            // 创建照片模型 (仅元数据)
            let photo = Photo(
                id: photoId, // 使用生成的 UUID
                albumId: albumId,
                fileName: fileName,
                createdAt: Date()
            )

            // 将刚创建的缩略图存入缓存
            let cacheKey = fileName as NSString
            // 计算 cost (可选, 基于像素数量或内存占用)
             let cost = Int(thumbnailImage.size.width * thumbnailImage.size.height * thumbnailImage.scale * 4) // 估算内存占用 (RGBA)
            imageCache.setObject(thumbnailImage, forKey: cacheKey, cost: cost)
             appLog("PhotoManager: 预缓存缩略图: \(fileName), cost: \(cost)")


            // 更新相册照片数量
            updateAlbumPhotoCount(albumId: albumId, change: 1)

             appLog("PhotoManager: 照片元数据保存成功: \(fileName)")
            return photo // 返回元数据 Photo
        } catch {
             appLog("PhotoManager: 保存照片文件失败: \(error)")
            // 尝试删除部分写入的文件（如果存在）
             _ = try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }


    // 创建高质量缩略图
    private func createHighQualityThumbnail(for image: UIImage, size: CGSize) -> UIImage? {
        // 检查原始图片大小，如果小于目标尺寸，直接返回原图可能更清晰
         if image.size.width < size.width && image.size.height < size.height {
            // return image // 可以选择返回原图，或者仍然强制缩放
         }

        // 使用 UIGraphicsImageRenderer 更现代、高效
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale // 适应屏幕分辨率
        format.opaque = true // JPEG 不需要透明度

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let thumbnail = renderer.image { context in
             // 计算保持宽高比的绘制区域 (center crop)
             let originalSize = image.size
             let targetSize = size
             let ratio = max(targetSize.width / originalSize.width, targetSize.height / originalSize.height)
             let newSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
             let drawRect = CGRect(
                 x: (targetSize.width - newSize.width) / 2,
                 y: (targetSize.height - newSize.height) / 2,
                 width: newSize.width,
                 height: newSize.height
             )

             image.draw(in: drawRect)
        }
        return thumbnail
    }

    // --- 新增：获取照片缩略图 (带缓存) ---
    func getThumbnail(for photo: Photo) -> UIImage? {
        let cacheKey = photo.fileName as NSString // 使用文件名作为缓存键

        // 1. 检查缓存
        if let cachedImage = imageCache.object(forKey: cacheKey) {
             appLog("PhotoManager: getThumbnail Cache hit for \(photo.fileName)")
            return cachedImage
        }
         appLog("PhotoManager: getThumbnail Cache miss for \(photo.fileName)")

        // 2. 从文件加载原图 (在后台队列执行耗时操作)
        guard let imagePath = photo.imagePath else {
             appLog("PhotoManager: getThumbnail Invalid image path for \(photo.fileName)")
             return nil
        }

        // 尝试轻量级加载，仅获取尺寸判断是否需要生成新缩略图 (可选优化)

        // 加载完整数据
        guard let imageData = try? Data(contentsOf: imagePath),
              let fullImage = UIImage(data: imageData) else {
             appLog("PhotoManager: getThumbnail Failed to load full image data for \(photo.fileName)")
            return nil // 加载失败
        }
         appLog("PhotoManager: getThumbnail Loaded full image for \(photo.fileName), size: \(fullImage.size)")

        // 3. 创建缩略图
        let thumbnailSize = CGSize(width: 300, height: 300) // 标准缩略图尺寸
        guard let thumbnail = createHighQualityThumbnail(for: fullImage, size: thumbnailSize) else {
             appLog("PhotoManager: getThumbnail Failed to create thumbnail for \(photo.fileName)")
            return nil
        }
         appLog("PhotoManager: getThumbnail Created thumbnail for \(photo.fileName), size: \(thumbnail.size)")

        // 4. 存入缓存
         let cost = Int(thumbnail.size.width * thumbnail.size.height * thumbnail.scale * 4)
        imageCache.setObject(thumbnail, forKey: cacheKey, cost: cost)
         appLog("PhotoManager: getThumbnail Stored thumbnail in cache for \(photo.fileName)")

        return thumbnail
    }
    // --- 结束新增 ---


    // 更新相册照片数量 (直接修改数据库)
    private func updateAlbumPhotoCount(albumId: UUID, change: Int) {
         appLog("PhotoManager: updateAlbumPhotoCount for album \(albumId) by \(change)")
        // 直接修改数据库中的计数值，避免重新扫描文件系统
        DispatchQueue.global(qos: .utility).async { // 在后台更新数据库
             // 1. 获取所有相册
             let allAlbums = DatabaseManager.shared.getAllAlbums()
             
             // 2. 查找需要更新的相册
             if var albumToUpdate = allAlbums.first(where: { $0.id == albumId }) {
                 // 3. 计算新数量并更新相册对象
                 let newCount = max(0, albumToUpdate.count + change) // 确保不为负
                 albumToUpdate.count = newCount
                 
                 // 4. 将更新后的相册写回数据库
                 if DatabaseManager.shared.updateAlbum(albumToUpdate) {
                      appLog("PhotoManager: Successfully updated album count in DB to \(newCount) for \(albumId)")
                 } else {
                      appLog("PhotoManager: Failed to update album count in DB for \(albumId)")
                 }
             } else {
                  // 如果没有找到相册，记录日志
                  appLog("PhotoManager: updateAlbumPhotoCount - Could not find album with id \(albumId) in DB to update count.")
             }
             // 注意：当前 DatabaseManager.getAllAlbums() 实现似乎不会抛出错误，所以未添加 try/catch
        }
    }


    // 获取相册中的所有照片 (仅元数据)
    func getPhotos(fromAlbum albumId: UUID) -> [Photo] {
        let fileManager = FileManager.default
        guard let albumDirectory = getAlbumDirectory(for: albumId) else {
             appLog("PhotoManager: getPhotos - Cannot get album directory for \(albumId)")
            return []
        }
         appLog("PhotoManager: getPhotos - Reading directory: \(albumDirectory.path)")

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: albumDirectory,
                                                                  includingPropertiesForKeys: [.creationDateKey], // 请求创建日期
                                                                  options: .skipsHiddenFiles)
            // 过滤出 .jpg 文件
             let photoFiles = fileURLs.filter { $0.pathExtension.lowercased() == "jpg" }
             appLog("PhotoManager: getPhotos - Found \(photoFiles.count) jpg files")


            var photos: [Photo] = []
            photos.reserveCapacity(photoFiles.count) // 预分配容量

            for fileURL in photoFiles {
                let fileName = fileURL.lastPathComponent
                // 从文件名解析 UUID (如果文件名是 UUID.jpg)
                let photoIdString = fileName.replacingOccurrences(of: ".jpg", with: "")
                guard let photoId = UUID(uuidString: photoIdString) else {
                     appLog("PhotoManager: getPhotos - Skipping file with invalid UUID name: \(fileName)")
                     continue // 跳过无效文件名的文件
                }


                do {
                    // 获取创建日期
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                    let creationDate = resourceValues.creationDate ?? Date() // 如果获取失败则使用当前日期

                    let photo = Photo(
                        id: photoId, // 使用从文件名解析的 ID
                        albumId: albumId,
                        fileName: fileName,
                        createdAt: creationDate
                        // 不再加载缩略图
                    )
                    photos.append(photo)
                } catch {
                     appLog("PhotoManager: getPhotos - Error getting attributes for \(fileName): \(error)")
                     // 可以选择跳过或用默认值
                     let photo = Photo(
                         id: photoId,
                         albumId: albumId,
                         fileName: fileName,
                         createdAt: Date()
                     )
                     photos.append(photo)
                }
            }

            // 按创建日期排序 (降序，最新的在前)
            return photos.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
             appLog("PhotoManager: getPhotos - Failed to list directory contents: \(error)")
            return []
        }
    }


    // 删除照片
    func deletePhoto(_ photo: Photo) -> Bool {
        guard let imagePath = photo.imagePath else {
            appLog("PhotoManager: deletePhoto - Invalid image path for \(photo.fileName)")
            return false
        }
        appLog("PhotoManager: deletePhoto - Attempting to delete \(photo.fileName)")

        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: imagePath)
            appLog("PhotoManager: deletePhoto - Successfully deleted file \(imagePath.path)")

            // 从缓存中移除缩略图
            let cacheKey = photo.fileName as NSString
            imageCache.removeObject(forKey: cacheKey)
            appLog("PhotoManager: deletePhoto - Removed thumbnail from cache for \(photo.fileName)")

            // 更新相册计数
            updateAlbumPhotoCount(albumId: photo.albumId, change: -1)

            return true
        } catch {
            appLog("PhotoManager: deletePhoto - Failed to delete file \(imagePath.path): \(error)")
            // 如果文件不存在，也可能认为是成功的删除操作 (例如重复删除)
            if (error as NSError).code == NSFileNoSuchFileError {
                appLog("PhotoManager: deletePhoto - File already deleted, treating as success.")
                // 仍然尝试更新计数和清除缓存，以防万一状态不一致
                let cacheKey = photo.fileName as NSString
                imageCache.removeObject(forKey: cacheKey)
                updateAlbumPhotoCount(albumId: photo.albumId, change: -1) // 确保计数正确
                return true
            }
            return false
        }
    }


    // 加载完整尺寸图片 (简单实现，无缓存)
    // 主要由详情页使用
    func loadFullImage(for photo: Photo) -> UIImage? {
        guard let imagePath = photo.imagePath else {
            appLog("PhotoManager: loadFullImage - Invalid image path for \(photo.fileName)")
            return nil
        }
         appLog("PhotoManager: loadFullImage - Loading full image from \(imagePath.path)")
        // 考虑在后台线程加载以避免阻塞
        guard let imageData = try? Data(contentsOf: imagePath) else {
            appLog("PhotoManager: loadFullImage - Failed to load image data for \(photo.fileName)")
            return nil
        }
        let image = UIImage(data: imageData)
        if image != nil {
             appLog("PhotoManager: loadFullImage - Successfully loaded full image for \(photo.fileName)")
        } else {
             appLog("PhotoManager: loadFullImage - Failed to create UIImage from data for \(photo.fileName)")
        }
        return image
    }

    // --- 与系统相册交互 (占位符，需要实现) ---
    func deletePhotosFromLibrary(identifiers: [String], completion: @escaping (Bool, Error?) -> Void) {
        appLog("PhotoManager: deletePhotosFromLibrary - Attempting to delete \(identifiers.count) photos from system library.")
        // 1. 检查权限
        let requiredAccessLevel: PHAccessLevel = .readWrite // 需要读写权限才能删除
        PHPhotoLibrary.requestAuthorization(for: requiredAccessLevel) { status in
            guard status == .authorized else {
                appLog("PhotoManager: deletePhotosFromLibrary - Photo Library access denied or limited.")
                completion(false, NSError(domain: "PhotoManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "照片库访问权限不足"]))
                return
            }

            // 2. 获取 PHAssets
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            if fetchResult.count == 0 {
                appLog("PhotoManager: deletePhotosFromLibrary - No matching assets found in the library for the given identifiers.")
                completion(true, nil) // 没有找到也算成功（可能已被删除）
                return
            }

            var assetsToDelete: [PHAsset] = []
            fetchResult.enumerateObjects { (asset, _, _) in
                assetsToDelete.append(asset)
            }

            appLog("PhotoManager: deletePhotosFromLibrary - Found \(assetsToDelete.count) assets to delete.")

            // 3. 执行删除
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        appLog("PhotoManager: deletePhotosFromLibrary - Successfully deleted photos from the library.")
                        completion(true, nil)
                    } else {
                        appLog("PhotoManager: deletePhotosFromLibrary - Failed to delete photos from the library: \(error?.localizedDescription ?? "Unknown error")")
                        completion(false, error)
                    }
                }
            }
        }
    }

    // --- 清理方法 (可选) ---
    func clearCache() {
        imageCache.removeAllObjects()
        appLog("PhotoManager: Cleared thumbnail cache.")
    }
}

// 添加对 UIImage 的扩展以辅助计算缓存成本 (可选)
extension UIImage {
    var approximateByteCount: Int {
        // 估算方式：宽度 * 高度 * 屏幕比例 * 4 (RGBA)
        // 对于压缩格式（如JPEG）这并不准确，但作为缓存成本的相对度量尚可
        return Int(size.width * size.height * scale * 4)
    }
}


// 确保 Photo 结构体也更新了 (如果它在另一个文件中)
// 已在此文件顶部更新

// 日志函数占位符 (确保你的项目中有 appLog 的实现)
/*
func appLog(_ message: String) { 
    // 将日志实现放在这里，例如：
    // print("[App Log] \(message)")
     NSLog("[App Log] %@", message) // 使用 NSLog 可以在 Console.app 中查看
} 
*/ 