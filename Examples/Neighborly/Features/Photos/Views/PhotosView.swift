import SwiftUIWeb

/// Photos: the people to pick from, then the albums of the one picked; an album opens in place, with its pictures.
struct PhotosView: View {
  let viewModel: PhotosViewModel
  let contacts: ContactsViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(PhotosStrings.title).font(.title2).fontWeight(.bold)
        PeoplePicker(people: contacts.people, selectedID: viewModel.personID) { id in
          Task { await viewModel.selectPerson(id) }
        }
        if let album = viewModel.album {
          AlbumView(viewModel: album) { viewModel.closeAlbum() }
        } else {
          AlbumsGrid(viewModel: viewModel)
        }
      }
      .padding(16)
      .frame(maxWidth: NeighborlyLayout.contentWidth)
      .frame(maxWidth: .infinity)
    }
  }
}
