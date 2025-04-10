import SwiftUI

struct AlbumView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("相册主界面")
                    .font(.largeTitle)
                    .padding()
                
                // 这里后续会添加相册网格视图
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        ForEach(0..<9) { _ in
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1, contentMode: .fit)
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("隐私相册")
        }
    }
}

#Preview {
    AlbumView()
} 