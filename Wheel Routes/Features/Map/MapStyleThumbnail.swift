import SwiftUI

struct MapStyleThumbnail: View {
    let option: MapStyleOption

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(option.thumbnailColor.gradient)
            .overlay {
                Image(systemName: option.thumbnailSymbolName)
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 44)
    }
}
