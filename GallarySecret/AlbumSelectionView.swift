import SwiftUI

struct AlbumSelectionView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let selectedPhotoIDs: Set<UUID>
    let currentAlbumId: UUID
    let onAlbumSelected: (UUID) -> Void
    
    @State private var albums: [Album] = []
    
    var body: some View {
        NavigationView {
            List {
                // Filter out the current album
                ForEach(albums.filter { $0.id != currentAlbumId }) { album in
                    Button(action: {
                        // Call the completion handler with the selected album ID
                        onAlbumSelected(album.id)
                        // Dismiss the sheet (handled by PhotoGridView setting state)
                        // presentationMode.wrappedValue.dismiss() // Not strictly needed if state dismisses
                    }) {
                        HStack {
                            // Display album cover thumbnail (simplified)
                            // You might want a proper thumbnail here later
                            Image(systemName: "photo.on.rectangle.angled") 
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
                                .padding(4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)

                            VStack(alignment: .leading) {
                                Text(album.name)
                                    .font(.headline)
                                Text("\(album.count) photos") // Use album.count directly
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right") // Indicate it's tappable
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundColor(.primary) // Ensure text color is standard
                }
            }
            .navigationTitle("Select Destination Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
            }
        }
    }
    
    private func loadAlbums() {
        self.albums = DatabaseManager.shared.getAllAlbums()
        // Optional: Sort albums, e.g., by name or creation date
        // self.albums.sort { $0.name < $1.name }
        appLog("AlbumSelectionView: Loaded \(albums.count) albums.")
    }
}

// Optional: Preview Provider
// struct AlbumSelectionView_Previews: PreviewProvider {
//     static var previews: some View {
//         // Create some dummy data for preview
//         let dummyUUID1 = UUID()
//         let dummyUUID2 = UUID()
//         let dummyUUID3 = UUID()
// 
//         AlbumSelectionView(
//             selectedPhotoIDs: [dummyUUID1],
//             currentAlbumId: dummyUUID2,
//             onAlbumSelected: { selectedId in
//                 print("Preview: Selected album ID \(selectedId)")
//             }
//         )
//     }
// } 