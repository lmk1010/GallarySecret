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
    }
}

struct AlbumsListView: View {
    @State private var albums: [Album] = sampleAlbums
    @State private var showingCreateSheet = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // 创建新相册卡片
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
                    
                    // 相册列表
                    ForEach(albums) { album in
                        NavigationLink(destination: PhotoGridView(album: album)) {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("隐私相册")
            .navigationBarItems(trailing: 
                Button(action: {
                    showingCreateSheet = true
                }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(isPresented: $showingCreateSheet) {
                CreateAlbumView(albums: $albums)
            }
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        }
    }
}

struct Album: Identifiable {
    let id = UUID()
    let name: String
    let coverImage: String
    let count: Int
    let createdAt: Date
}

struct AlbumCard: View {
    let album: Album
    @Environment(\.colorScheme) var colorScheme
    
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

struct PhotoGridView: View {
    let album: Album
    @State private var gridLayout = [GridItem(.adaptive(minimum: 100))]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridLayout, spacing: 10) {
                ForEach(0..<(album.count == 0 ? 9 : album.count), id: \.self) { _ in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? 
                                  Color(UIColor.systemGray5) : Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                        
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                            .foregroundColor(colorScheme == .dark ? Color.gray.opacity(0.7) : .gray)
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), 
                            radius: 2, x: 0, y: 1)
                }
            }
            .padding()
        }
        .navigationTitle(album.name)
        .navigationBarItems(trailing:
            HStack {
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button(action: {}) {
                    Image(systemName: "plus")
                }
            }
        )
        .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
    }
}

struct CreateAlbumView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var albums: [Album]
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
                        albums.append(newAlbum)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(albumName.isEmpty)
            )
        }
    }
}

struct ProfileView: View {
    @Environment(\.colorScheme) var colorScheme
    
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
                            Text("0.0 MB")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Label("安全设置", systemImage: "lock.shield")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
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
        }
    }
}

// 示例数据
let sampleAlbums = [
    Album(
        name: "生活记忆",
        coverImage: "",
        count: 24,
        createdAt: Date().addingTimeInterval(-86400 * 7)
    ),
    Album(
        name: "旅行",
        coverImage: "",
        count: 56,
        createdAt: Date().addingTimeInterval(-86400 * 30)
    ),
    Album(
        name: "工作",
        coverImage: "",
        count: 12,
        createdAt: Date().addingTimeInterval(-86400 * 2)
    )
]

#Preview {
    MainView()
} 