    //
    //  SystemEventIndicatorModifier.swift
    //  boringNotch
    //
    //  Created by Richard Kunkli on 12/08/2024.
    //

import SwiftUI
import Defaults

struct SystemEventIndicatorModifier: View {
    @Environment(\.islandAppearance) private var islandAppearance
    @EnvironmentObject var vm: BoringViewModel
    @Binding var eventType: SneakContentType
    @Binding var value: CGFloat {
        didSet {
            DispatchQueue.main.async {
                self.sendEventBack(value)
                self.vm.objectWillChange.send()
            }
        }
    }
    @Binding var icon: String
    let showSlider: Bool = false
    var sendEventBack: (CGFloat) -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            switch (eventType) {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.interpolate)
                            .symbolVariant(value > 0 ? .none : .slash)
                            .frame(width: 20, height: 15, alignment: .leading)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                            .opacity(value.isZero ? 0.6 : 1)
                            .scaleEffect(value.isZero ? 0.85 : 1)
                            .frame(width: 20, height: 15, alignment: .leading)
                    }
                case .brightness:
                    Image(systemName: "sun.max.fill")
                        .contentTransition(.symbolEffect)
                        .frame(width: 20, height: 15)
                        .foregroundStyle(islandAppearance.primary)
                case .backlight:
                    Image(systemName: value > 0.5 ? "light.max" : "light.min")
                        .contentTransition(.interpolate)
                        .frame(width: 20, height: 15)
                        .foregroundStyle(islandAppearance.primary)
                case .mic:
                    Image(systemName: "mic")
                        .symbolVariant(value > 0 ? .none : .slash)
                        .contentTransition(.interpolate)
                        .frame(width: 20, height: 15)
                        .foregroundStyle(islandAppearance.primary)
                default:
                    EmptyView()
            }
            if (eventType != .mic) {
                DraggableProgressBar(value: $value)
            } else {
                Text(String(format: L("Mic %@"), L(value > 0 ? "unmuted" : "muted")))
                    .foregroundStyle(islandAppearance.secondary)
                    .lineLimit(1)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .symbolVariant(.fill)
        .imageScale(.large)
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker.slash"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
}

struct DraggableProgressBar: View {
    @Environment(\.islandAppearance) private var islandAppearance
    @EnvironmentObject var vm: BoringViewModel
    @Binding var value: CGFloat
    @Default(.enableGradient) private var enableGradient
    @Default(.systemEventIndicatorUseAccent) private var systemEventIndicatorUseAccent
    @Default(.systemEventIndicatorShadow) private var systemEventIndicatorShadow
    @Default(.inlineHUD) private var inlineHUD
    var onChange: ((CGFloat) -> Void)? = nil
    
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        VStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(islandAppearance.track)
                    Capsule()
                        .fill(
                            enableGradient ?
                                AnyShapeStyle(LinearGradient(
                                    colors: systemEventIndicatorUseAccent ?
                                        [Color.effectiveAccent, Color.effectiveAccent.ensureMinimumBrightness(factor: 0.2)] :
                                        [islandAppearance.primary, islandAppearance.primary.opacity(0.2)],
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )) :
                                AnyShapeStyle(systemEventIndicatorUseAccent ? Color.effectiveAccent : islandAppearance.primary)
                        )
                        .frame(width: max(0, min(geo.size.width * value, geo.size.width)))
                        .shadow(color: systemEventIndicatorShadow ?
                            (systemEventIndicatorUseAccent ?
                                Color.effectiveAccent.ensureMinimumBrightness(factor: 0.7) :
                                islandAppearance.primary) :
                            Color.clear,
                            radius: 8, x: 3)
                        .opacity(value.isZero ? 0 : 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = true
                                updateValue(gesture: gesture, in: geo)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: inlineHUD ? isDragging ? 8 : 5 : isDragging ? 9 : 6)
        }
    }
    
    private func updateValue(gesture: DragGesture.Value, in geometry: GeometryProxy) {
        let dragPosition = gesture.location.x
        let newValue = dragPosition / geometry.size.width
        
        value = max(0, min(newValue, 1))
        onChange?(value)
    }
}
