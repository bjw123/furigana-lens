import SwiftUI
import PhotosUI

extension ScanView {

    // MARK: - Live camera

    var liveCameraView: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            camera.setZoom(pinchBaseZoom * scale)
                        }
                        .onEnded { _ in
                            pinchBaseZoom = camera.zoomFactor
                        }
                )
                .onAppear { pinchBaseZoom = camera.zoomFactor }

            if camera.zoomFactor > 1.05 {
                HStack {
                    Spacer()
                    Text(String(format: "%.1f×", camera.zoomFactor))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.32)))
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if camera.permissionDenied {
                ContentUnavailableView(
                    "Camera Access Required",
                    systemImage: "camera.fill",
                    description: Text("Enable camera access in Settings to scan Japanese text from your TV.")
                )
                .background(.ultraThinMaterial)
            } else {
                bottomControlBar
            }
        }
    }

    var bottomControlBar: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("TVの日本語にカメラを向けて、撮影してください。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                Text("Aim at Japanese text and tap to capture")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .blur(radius: 4)
            )
            .padding(.horizontal, 24)

            HStack(alignment: .center, spacing: 28) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(.white)
                            .background(Circle().fill(.white.opacity(0.16)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 0.75))
                        Text("Photos")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Button {
                    Task { await captureAndProcess() }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Palette.sakura.opacity(0.95), lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(LinearGradient(
                                colors: [Palette.indigo, Palette.indigo.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 64, height: 64)
                            .shadow(color: Palette.indigo.opacity(0.4), radius: 12, y: 4)
                        Image(systemName: "camera.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel("Capture")

                Button {
                    showManualLookup = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "character.cursor.ibeam")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(.white)
                            .background(Circle().fill(.white.opacity(0.16)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 0.75))
                        Text("Keyboard")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.20),
                    Palette.indigoDeep.opacity(0.35),
                    Palette.sumi.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
