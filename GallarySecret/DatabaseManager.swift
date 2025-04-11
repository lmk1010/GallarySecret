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
            print("无法打开数据库连接")
            return
        }
        
        // 创建相册表
        let createTableString = """
        CREATE TABLE IF NOT EXISTS albums(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cover_image TEXT,
            count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
        );
        """
        
        // 执行创建表的 SQL 语句
        if sqlite3_exec(database, createTableString, nil, nil, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("创建表失败: \(errorMessage)")
            return
        }
        
        print("数据库和表创建成功")
    }
    
    // 保存相册
    func saveAlbum(_ album: Album) -> Bool {
        var result = false
        
        // 使用串行队列执行数据库操作
        dbLock.lock()
        dbQueue.sync {
            let insertStatementString = "INSERT INTO albums (id, name, cover_image, count, created_at) VALUES (?, ?, ?, ?, ?);"
            var insertStatement: OpaquePointer?
            
            // 准备 SQL 语句
            if sqlite3_prepare_v2(database, insertStatementString, -1, &insertStatement, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("准备插入语句失败: \(errorMessage)")
                result = false
                return
            }
            
            // 绑定参数
            let idString = album.id.uuidString
            sqlite3_bind_text(insertStatement, 1, (idString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (album.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (album.coverImage as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 4, Int32(album.count))
            
            let dateFormatter = ISO8601DateFormatter()
            let dateString = dateFormatter.string(from: album.createdAt)
            sqlite3_bind_text(insertStatement, 5, (dateString as NSString).utf8String, -1, nil)
            
            // 执行插入
            if sqlite3_step(insertStatement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("插入数据失败: \(errorMessage)")
                sqlite3_finalize(insertStatement)
                result = false
                return
            }
            
            // 释放语句
            sqlite3_finalize(insertStatement)
            print("相册保存成功")
            result = true
        }
        dbLock.unlock()
        
        return result
    }
    
    // 获取所有相册
    func getAllAlbums() -> [Album] {
        var albums = [Album]()
        
        // 使用串行队列执行数据库操作
        dbLock.lock()
        dbQueue.sync {
            let queryStatementString = "SELECT id, name, cover_image, count, created_at FROM albums ORDER BY created_at DESC;"
            var queryStatement: OpaquePointer?
            
            // 准备 SQL 语句
            if sqlite3_prepare_v2(database, queryStatementString, -1, &queryStatement, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("准备查询语句失败: \(errorMessage)")
                return
            }
            
            // 执行查询
            let dateFormatter = ISO8601DateFormatter()
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(queryStatement, 0))
                let name = String(cString: sqlite3_column_text(queryStatement, 1))
                
                let coverImage: String
                if let coverImagePtr = sqlite3_column_text(queryStatement, 2) {
                    coverImage = String(cString: coverImagePtr)
                } else {
                    coverImage = ""
                }
                
                let count = Int(sqlite3_column_int(queryStatement, 3))
                let dateString = String(cString: sqlite3_column_text(queryStatement, 4))
                let createdAt = dateFormatter.date(from: dateString) ?? Date()
                
                if let uuid = UUID(uuidString: idString) {
                    let album = Album(id: uuid, name: name, coverImage: coverImage, count: count, createdAt: createdAt)
                    albums.append(album)
                }
            }
            
            // 释放语句
            sqlite3_finalize(queryStatement)
        }
        dbLock.unlock()
        
        return albums
    }
    
    // 更新相册
    func updateAlbum(_ album: Album) -> Bool {
        var result = false
        
        // 使用串行队列执行数据库操作
        dbLock.lock()
        dbQueue.sync {
            let updateStatementString = "UPDATE albums SET name = ?, cover_image = ?, count = ? WHERE id = ?;"
            var updateStatement: OpaquePointer?
            
            // 准备 SQL 语句
            if sqlite3_prepare_v2(database, updateStatementString, -1, &updateStatement, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("准备更新语句失败: \(errorMessage)")
                result = false
                return
            }
            
            // 绑定参数
            sqlite3_bind_text(updateStatement, 1, (album.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStatement, 2, (album.coverImage as NSString).utf8String, -1, nil)
            sqlite3_bind_int(updateStatement, 3, Int32(album.count))
            sqlite3_bind_text(updateStatement, 4, (album.id.uuidString as NSString).utf8String, -1, nil)
            
            // 执行更新
            if sqlite3_step(updateStatement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("更新数据失败: \(errorMessage)")
                sqlite3_finalize(updateStatement)
                result = false
                return
            }
            
            // 释放语句
            sqlite3_finalize(updateStatement)
            print("相册更新成功")
            result = true
        }
        dbLock.unlock()
        
        return result
    }
    
    // 删除相册
    func deleteAlbum(id: UUID) -> Bool {
        var result = false
        
        // 使用串行队列执行数据库操作
        dbLock.lock()
        dbQueue.sync {
            let deleteStatementString = "DELETE FROM albums WHERE id = ?;"
            var deleteStatement: OpaquePointer?
            
            // 准备 SQL 语句
            if sqlite3_prepare_v2(database, deleteStatementString, -1, &deleteStatement, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("准备删除语句失败: \(errorMessage)")
                result = false
                return
            }
            
            // 绑定参数
            sqlite3_bind_text(deleteStatement, 1, (id.uuidString as NSString).utf8String, -1, nil)
            
            // 执行删除
            if sqlite3_step(deleteStatement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("删除数据失败: \(errorMessage)")
                sqlite3_finalize(deleteStatement)
                result = false
                return
            }
            
            // 释放语句
            sqlite3_finalize(deleteStatement)
            print("相册删除成功")
            result = true
        }
        dbLock.unlock()
        
        return result
    }
} 