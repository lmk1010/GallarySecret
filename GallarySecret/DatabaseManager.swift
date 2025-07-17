import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    private var database: OpaquePointer?
    private let databaseName = "gallery_secret.sqlite"
    
    // 添加串行队列和锁，确保数据库操作的线程安全
    private let dbQueue = DispatchQueue(label: "com.gallerySecret.databaseQueue", qos: .utility)
    private let dbLock = NSLock()
    
    private init() {
        setupDatabase()
    }
    
    // 设置数据库
    private func setupDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(databaseName)
        
        // 打开数据库连接
        if sqlite3_open(fileURL.path, &database) != SQLITE_OK {
            print("Unable to open database connection")
            return
        }
        
        // 创建相册表
        let createAlbumTableString = """
        CREATE TABLE IF NOT EXISTS albums(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cover_image TEXT,
            count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
        );
        """
        
        // 执行创建表的 SQL 语句
        if sqlite3_exec(database, createAlbumTableString, nil, nil, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("Failed to create album table: \(errorMessage)")
            return
        }
        
        print("Database and table created successfully")
    }
    
    // 保存相册
    func saveAlbum(_ album: Album) -> Bool {
        dbLock.lock()
        defer { dbLock.unlock() }
        
        let insertString = "INSERT INTO albums (id, name, cover_image, count, created_at) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(database, insertString, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("Failed to prepare insert: \(errorMessage)")
            return false
        }
        
        let id = album.id.uuidString
        let name = album.name
        let coverImage = album.coverImage
        let count = Int32(album.count)
        let createdAt = ISO8601DateFormatter().string(from: album.createdAt)
        
        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (coverImage as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 4, count)
        sqlite3_bind_text(statement, 5, (createdAt as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("Insert failed: \(errorMessage)")
            sqlite3_finalize(statement)
            return false
        }
        
        sqlite3_finalize(statement)
        return true
    }
    
    // 获取所有相册
    func getAllAlbums() -> [Album] {
        dbLock.lock()
        defer { dbLock.unlock() }
        
        let queryString = "SELECT id, name, cover_image, count, created_at FROM albums ORDER BY created_at DESC;"
        var statement: OpaquePointer?
        var albums: [Album] = []
        
        if sqlite3_prepare_v2(database, queryString, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("Failed to prepare query: \(errorMessage)")
            return albums
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let coverImage = String(cString: sqlite3_column_text(statement, 2))
            let count = sqlite3_column_int(statement, 3)
            let createdAtString = String(cString: sqlite3_column_text(statement, 4))
            
            if let uuid = UUID(uuidString: id),
               let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                let album = Album(
                    id: uuid,
                    name: name,
                    coverImage: coverImage,
                    count: Int(count),
                    createdAt: createdAt
                )
                albums.append(album)
            }
        }
        
        sqlite3_finalize(statement)
        return albums
    }
    
    // 删除相册
    func deleteAlbum(withId id: UUID) -> Bool {
        dbLock.lock()
        defer { dbLock.unlock() }
        
        let deleteString = "DELETE FROM albums WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(database, deleteString, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("Failed to prepare delete: \(errorMessage)")
            return false
        }
        
        let idString = id.uuidString
        sqlite3_bind_text(statement, 1, (idString as NSString).utf8String, -1, nil)
        
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }
    
    // 更新相册信息
    func updateAlbum(_ album: Album) -> Bool {
        dbLock.lock()
        defer { dbLock.unlock() }
        
        // 修复：添加详细日志帮助调试
        print("DatabaseManager: updateAlbum - Starting to update album")
        print("DatabaseManager: updateAlbum - Album ID: \(album.id.uuidString)")
        print("DatabaseManager: updateAlbum - Album name: \(album.name)")
        print("DatabaseManager: updateAlbum - Photo count: \(album.count)")
        
        let updateString = "UPDATE albums SET name = ?, cover_image = ?, count = ? WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(database, updateString, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("DatabaseManager: updateAlbum - Failed to prepare update: \(errorMessage)")
            return false
        }
        
        let name = album.name
        let coverImage = album.coverImage
        let count = Int32(album.count)
        let id = album.id.uuidString
        
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (coverImage as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 3, count)
        sqlite3_bind_text(statement, 4, (id as NSString).utf8String, -1, nil)
        
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        // 修复：添加结果日志
        print("DatabaseManager: updateAlbum - Update result: \(result ? "Success" : "Failed")")
        if result {
            print("DatabaseManager: updateAlbum - Album '\(album.name)' updated successfully, photo count: \(album.count)")
        }
        
        return result
    }
} 