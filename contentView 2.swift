import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = GyroManager()
    @State private var showCameraView = false
    @State private var flattenRequested = false


    var body: some View {
        VStack {
            if showCameraView {
                VStack {
                    CameraOCRView(flattenRequested: $flattenRequested)

                    Button(action: {
                        flattenRequested.toggle()
                    }) {
                        Text("Kép kiegyenesítése")
                            .bold()
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 30) {
                    Text("Telefon orientáció")
                        .font(.title)
                        .bold()
                    
                    VStack(spacing: 10) {
                        Text("Pitch: \(motionManager.pitch * 180 / .pi, specifier: "%.2f")°")
                        Text("Roll:  \(motionManager.roll * 180 / .pi, specifier: "%.2f")°")
                        Text("Yaw:   \(motionManager.yaw * 180 / .pi, specifier: "%.2f")°")
                    }
                    .font(.system(size: 18, weight: .medium))
                    
                    Spacer()
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]),
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 150, height: 300)
                        .rotation3DEffect(
                            .degrees(motionManager.pitch * 180 / .pi),
                            axis: (x: 1, y: 0, z: 0)
                        )
                        .rotation3DEffect(
                            .degrees(motionManager.roll * 180 / .pi),
                            axis: (x: 0, y: 0, z: 1)
                        )
                        .shadow(radius: 10)

                    Text("↑ Ez a telefon dőlése")
                        .font(.caption)
                        .padding(.top, 5)
                    
                    Spacer()
                }
                .padding()
            }
            
            Button(action: {
                showCameraView.toggle()
            }) {
                Text(showCameraView ? "Mutasd az orientációt" : "Kamera + OCR mód")
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding()
            }
        }
    }
}
