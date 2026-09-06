//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

private let tabs = [
    TabModel(label: "小岛", icon: "leaf.fill", view: .island),
    TabModel(label: "工具主页", icon: "house.fill", view: .home),
    TabModel(label: "文件暂存", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    var compact = false
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var shelfEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var animation

    private var availableTabs: [TabModel] {
        tabs.filter { $0.view != .shelf || shelfEnabled }
    }

    var body: some View {
        if compact {
            Menu {
                ForEach(availableTabs) { tab in
                    Button { select(tab) } label: { Label(L(tab.label), systemImage: tab.icon) }
                }
            } label: {
                let selected = tabs.first { $0.view == coordinator.currentView } ?? tabs[0]
                Label(L(selected.label), systemImage: selected.icon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("切换小岛与工具")
        } else {
            segmentedTabs
        }
    }

    private var segmentedTabs: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs) { tab in
                    TabButton(label: L(tab.label), icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        select(tab)
                    }
                    .help(L(tab.label))
                    .accessibilityLabel(L(tab.label))
                    .accessibilityAddTraits(tab.view == coordinator.currentView ? .isSelected : [])
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }

    private func select(_ tab: TabModel) {
        withAnimation(reduceMotion ? nil : .smooth) {
            coordinator.currentView = tab.view
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
