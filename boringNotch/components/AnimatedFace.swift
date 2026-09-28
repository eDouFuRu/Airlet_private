import SwiftUI

/// Keeps user input and the closed-island geometry in agreement.
enum IdleEmojiLayout {
    static func characters(in text: String) -> [String] {
        Array(text.prefix(3)).map(String.init)
    }

    static func normalized(_ text: String) -> String { characters(in: text).joined() }

    static func wingWidth(for text: String) -> CGFloat {
        let count = characters(in: text).count
        return count == 0 ? 0 : 16 + CGFloat(count * 22 + (count - 1) * 2)
    }
}

struct IdleEmojiWing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false
    let characters: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                Text(character)
                    .font(.system(size: 17))
                    .frame(width: 22, height: 24)
            }
        }
        .offset(y: raised && !reduceMotion ? -1.5 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                raised = true
            }
        }
        .onDisappear { raised = false }
        .accessibilityElement(children: .combine)
    }
}

struct MinimalFaceFeatures: View {
    @Environment(\.islandAppearance) private var islandAppearance
    @State private var isBlinking = false
    @State var height:CGFloat = 20;
    @State var width:CGFloat = 30;
    
    var body: some View {
        VStack(spacing: 4) { // Adjusted spacing to fit within 30x30
            // Eyes
            HStack(spacing: 4) { // Adjusted spacing to fit within 30x30
                Eye(isBlinking: $isBlinking)
                Eye(isBlinking: $isBlinking)
            }
            
            // Nose and mouth combined
            VStack(spacing: 2) { // Adjusted spacing to fit within 30x30
                // Nose
                RoundedRectangle(cornerRadius: 2)
                    .fill(islandAppearance.primary)
                    .frame(width: 3, height: 4)
                
                // Mouth (happy)
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: height))
                    }
                    .stroke(islandAppearance.primary, lineWidth: 2)
                }
                .frame(width: 14, height: 10)
            }
        }
        .frame(width: self.width, height: self.height) // Maximum size of face
        .onAppear {
            startBlinking()
        }
    }
    
    func startBlinking() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            withAnimation(.spring(duration: 0.2)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(duration: 0.2)) {
                    isBlinking = false
                }
            }
        }
    }
}

struct Eye: View {
    @Environment(\.islandAppearance) private var islandAppearance
    @Binding var isBlinking: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(islandAppearance.primary)
            .frame(width: 4, height: isBlinking ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15) // Adjusted max size
            .animation(.easeInOut(duration: 0.1), value: isBlinking)
    }
}
