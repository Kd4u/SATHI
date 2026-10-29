#if os(iOS)
import SwiftUI
import UIKit

struct AccentTabBar: UIViewRepresentable {
    let color: Color
    func makeUIView(context: Context) -> TintView { TintView() }
    func updateUIView(_ view: TintView, context: Context) {
        view.tint = UIColor(color)
        DispatchQueue.main.async { [weak view] in view?.apply() }
    }
    final class TintView: UIView {
        var tint = UIColor.systemBlue
        override func didMoveToWindow() { super.didMoveToWindow(); apply() }
        func apply() {
            func find(_ controller: UIViewController?) -> UITabBarController? {
                guard let controller else { return nil }
                if let tab = controller as? UITabBarController { return tab }
                for child in controller.children { if let value = find(child) { return value } }
                return nil
            }
            guard let tab = find(window?.rootViewController) else { return }
            tab.tabBar.tintColor = tint
            tab.tabBar.unselectedItemTintColor = tint.withAlphaComponent(0.75)
        }
    }
}
#endif
