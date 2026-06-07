import SwiftUI

struct ZoomableImageView: View {
    let image: UIImage
    var lines: [OCRLine] = []
    var highlightedToken: JapaneseToken? = nil

    @State private var scale: CGFloat = 1.0
    @State private var pinchBase: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(highlightOverlay(in: geo.size))
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = clamp(pinchBase * value)
                            }
                            .onEnded { _ in
                                pinchBase = scale
                                if scale <= 1.0 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        offset = .zero
                                        dragBase = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: dragBase.width + value.translation.width,
                                    height: dragBase.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                dragBase = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1.0 {
                            scale = 1.0
                            pinchBase = 1.0
                            offset = .zero
                            dragBase = .zero
                        } else {
                            scale = 2.5
                            pinchBase = 2.5
                        }
                    }
                }
        }
        .contentShape(Rectangle())
        .clipped()
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        max(minScale, min(value, maxScale))
    }

    @ViewBuilder
    private func highlightOverlay(in size: CGSize) -> some View {
        if let bbox = highlightedTokenBox() {
            let rect = mapBox(bbox, in: size)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.sakura.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Palette.sakura.opacity(0.9), lineWidth: 1 / max(scale, 1))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func mapBox(_ bbox: CGRect, in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fit = min(size.width / imageSize.width, size.height / imageSize.height)
        let displayedW = imageSize.width * fit
        let displayedH = imageSize.height * fit
        let offsetX = (size.width - displayedW) / 2
        let offsetY = (size.height - displayedH) / 2
        return CGRect(
            x: offsetX + bbox.minX * displayedW,
            y: offsetY + (1 - bbox.maxY) * displayedH,
            width: bbox.width * displayedW,
            height: bbox.height * displayedH
        )
    }

    private func highlightedTokenBox() -> CGRect? {
        guard let token = highlightedToken,
              let lineId = token.lineId,
              let charRange = token.lineCharRange,
              let line = lines.first(where: { $0.id == lineId }),
              !line.charBoxes.isEmpty
        else { return nil }

        let lower = max(0, min(charRange.lowerBound, line.charBoxes.count - 1))
        let upper = max(lower + 1, min(charRange.upperBound, line.charBoxes.count))
        let boxes = Array(line.charBoxes[lower..<upper])
        guard !boxes.isEmpty else { return nil }
        return boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
    }
}
