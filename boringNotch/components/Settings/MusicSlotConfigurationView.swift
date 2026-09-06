// Derived from boring.notch v2.7.3. Pure configuration preview and private drag payloads.
import Defaults
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @State private var selectedSlot: Int?
    @State private var paletteTargeted = false
    @State private var trashTargeted = false
    @State private var needsTarget = false
    private static let dragType = "com.dongfengrui.NotchIsland.media-control"
    private var slots: [MusicControlButton] { MusicControlButton.normalized(musicControlSlots) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout Preview").font(.headline).foregroundStyle(.secondary)
            Text(L("Drag to move or swap. Return a control to the library to remove it."))
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(0..<MediaSlotReducer.slotCount, id: \.self) { index in
                        previewSlot(at: index)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                VStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 17))
                        .frame(width: 48, height: 48)
                        .background(trashTargeted ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .onDrop(of: [Self.dragType], isTargeted: $trashTargeted) { acceptDrop($0, at: nil) }
                        .accessibilityLabel(Text(L("Clear slot")))
                    Text("Clear slot").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text(L("Control library")).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(MusicControlButton.pickerOptions, id: \.self) { control in
                        VStack(spacing: 5) {
                            controlTile(control)
                                .overlay(alignment: .topTrailing) {
                                    if slots.contains(control) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                                            .offset(x: 3, y: -3).accessibilityHidden(true)
                                    }
                                }
                                .onDrag { provider(for: control, source: nil) }
                                .onTapGesture { addFromLibrary(control) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text(L(control.label)))
                                .accessibilityAction { addFromLibrary(control) }
                            Text(L(control.label))
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 62).multilineTextAlignment(.center).lineLimit(2)
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.visible)
            .background(paletteTargeted ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onDrop(of: [Self.dragType], isTargeted: $paletteTargeted) { acceptDrop($0, at: nil) }
            if needsTarget {
                Text(L("Select a slot to replace, or drag a control onto it."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    musicControlSlots = MusicControlButton.defaultLayout
                    selectedSlot = nil
                    needsTarget = false
                }.buttonStyle(.borderless)
            }
        }
        .onAppear {
            let canonical = slots
            if canonical != musicControlSlots { musicControlSlots = canonical }
        }
    }

    @ViewBuilder private func previewSlot(at index: Int) -> some View {
        let control = slots[index]
        let tile = controlTile(control)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedSlot == index ? Color.accentColor : .clear, lineWidth: 2)
            }
            .onTapGesture { selectedSlot = index; needsTarget = false }
            .onDrop(of: [Self.dragType], isTargeted: nil) { acceptDrop($0, at: index) }
            .accessibilityLabel(Text("\(L("Slot")) \(index + 1): \(L(control.label))"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selectedSlot = index; needsTarget = false }
        if control == .none {
            tile
        } else {
            tile.onDrag { provider(for: control, source: index) }
                .overlay(alignment: .topTrailing) {
                    Button { removeSlot(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, Color(NSColor.controlBackgroundColor))
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help(L("Remove control"))
                    .accessibilityLabel(Text(L("Remove control") + ": " + L(control.label)))
                    .offset(x: 4, y: -4)
                }
                .contextMenu { Button(L("Remove control")) { removeSlot(index) } }
        }
    }

    /// No player, notch state, side effects, or runtime controls enter this preview.
    private func controlTile(_ control: MusicControlButton) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor))
            if control == .none {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.4)).padding(6)
            } else {
                Image(systemName: control.iconName)
                    .font(.system(size: control.prefersLargeScale ? 18 : 15, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func provider(for control: MusicControlButton, source: Int?) -> NSItemProvider {
        let payload = MediaControlDragPayload(controlID: control.rawValue, sourceSlot: source)
        let data = try? JSONEncoder().encode(payload)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func acceptDrop(_ providers: [NSItemProvider], at target: Int?) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.dragType) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: Self.dragType) { data, _ in
            guard let data, data.count <= 1_024,
                  let payload = try? JSONDecoder().decode(MediaControlDragPayload.self, from: data),
                  let control = MusicControlButton(rawValue: payload.controlID), control != .none else { return }
            Task { @MainActor in
                apply(payload, to: target)
            }
        }
        return true
    }

    private func apply(_ payload: MediaControlDragPayload, to target: Int?) {
        musicControlSlots = MusicControlButton.applying(payload, to: target, in: musicControlSlots)
        selectedSlot = target
        needsTarget = false
    }

    private func removeSlot(_ index: Int) {
        apply(MediaControlDragPayload(controlID: slots[index].rawValue, sourceSlot: index), to: nil)
    }

    private func addFromLibrary(_ control: MusicControlButton) {
        guard let target = selectedSlot ?? slots.firstIndex(of: control) ?? slots.firstIndex(of: .none) else {
            needsTarget = true
            return
        }
        apply(MediaControlDragPayload(controlID: control.rawValue, sourceSlot: nil), to: target)
    }
}
