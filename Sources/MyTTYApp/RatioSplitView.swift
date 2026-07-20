import AppKit
import MyTTYCore

@MainActor
final class RatioSplitView: NSSplitView, NSSplitViewDelegate {
    private var currentRatio: Double
    private let onRatioChanged: (Double) -> Void
    private let onUserResize: () -> Void
    private var lastReportedRatio: Double?

    init(
        orientation: SplitOrientation,
        ratio: Double,
        onRatioChanged: @escaping (Double) -> Void,
        onUserResize: @escaping () -> Void = {}
    ) {
        currentRatio = ratio
        self.onRatioChanged = onRatioChanged
        self.onUserResize = onUserResize
        super.init(frame: .zero)
        isVertical = orientation == .horizontal
        dividerStyle = .thin
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyCurrentRatio() {
        guard subviews.count == 2 else { return }
        let available = splitDimension - dividerThickness
        guard available > 0 else { return }
        setPosition(available * currentRatio, ofDividerAt: 0)
        lastReportedRatio = currentRatio
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let userResize = notification.userInfo?[
                  "NSSplitViewUserResizeKey"
              ] as? NSNumber,
              userResize.boolValue,
              subviews.count == 2
        else { return }
        let available = splitDimension - dividerThickness
        guard available > 0 else { return }

        let ratio = min(0.95, max(0.05, firstPaneRatio))
        guard lastReportedRatio.map({ abs($0 - ratio) >= 0.001 }) ?? true
        else { return }
        currentRatio = ratio
        lastReportedRatio = ratio
        onRatioChanged(ratio)
        onUserResize()
    }

    var firstPaneRatio: Double {
        let available = splitDimension - dividerThickness
        guard subviews.count == 2, available > 0 else { return currentRatio }
        let firstDimension = isVertical
            ? subviews[0].frame.width
            : subviews[0].frame.height
        return firstDimension / available
    }

    private var splitDimension: CGFloat {
        isVertical ? bounds.width : bounds.height
    }
}
