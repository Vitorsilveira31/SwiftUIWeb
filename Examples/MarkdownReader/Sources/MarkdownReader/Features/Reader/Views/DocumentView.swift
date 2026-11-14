import SwiftUI

/// The document as one lazy column, one row per block. Links to an anchor in
/// this document scroll to it; every other link goes to the system.
struct DocumentView: View {
    let document: Document
    let scrollRequest: ScrollRequest?
    let textSize: TextSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(document.blocks) { block in
                        BlockView(block: block)
                            .id(block.id)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == nil, url.absoluteString.hasPrefix("#") else {
                    return .systemAction(url)
                }
                let anchor = String(url.absoluteString.dropFirst())
                if let blockID = document.anchors[anchor] {
                    withAnimation {
                        proxy.scrollTo(blockID, anchor: .top)
                    }
                }
                return .handled
            })
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                withAnimation {
                    proxy.scrollTo(request.blockID, anchor: .top)
                }
            }
            .dynamicTypeSize(textSize.dynamicTypeSize)
        }
    }
}
