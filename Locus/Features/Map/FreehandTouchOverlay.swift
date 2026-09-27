import SwiftUI
import UIKit

struct FreehandCanvasTouchOverlay: UIViewRepresentable {
    var isDrawingEnabled: Bool = true
    var onPoint: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> FreehandTouchView {
        let view = FreehandTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.onPoint = onPoint
        view.onEnded = onEnded
        view.isDrawingEnabled = isDrawingEnabled
        return view
    }

    func updateUIView(_ uiView: FreehandTouchView, context: Context) {
        uiView.onPoint = onPoint
        uiView.onEnded = onEnded
        uiView.isDrawingEnabled = isDrawingEnabled
    }
}

final class FreehandTouchView: UIView {
    var isDrawingEnabled: Bool = true
    var onPoint: ((CGPoint) -> Void)?
    var onEnded: (() -> Void)?
    private var isTrackingSingleTouch = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isDrawingEnabled else {
            // When drawing is disabled, let all gestures pass through to map
            return nil
        }

        // When 2 or more fingers are touching, pass through to MKMapView for pan / pinch / scroll
        if let all = event?.allTouches, all.count >= 2 {
            if isTrackingSingleTouch {
                isTrackingSingleTouch = false
                onEnded?()
            }
            return nil
        }
        return super.hitTest(point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let all = event?.allTouches, all.count >= 2 {
            if isTrackingSingleTouch {
                isTrackingSingleTouch = false
                onEnded?()
            }
            return
        }
        guard let touch = touches.first else { return }
        isTrackingSingleTouch = true
        onPoint?(touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let all = event?.allTouches, all.count >= 2 {
            if isTrackingSingleTouch {
                isTrackingSingleTouch = false
                onEnded?()
            }
            return
        }
        guard isTrackingSingleTouch, let touch = touches.first else { return }
        onPoint?(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isTrackingSingleTouch {
            isTrackingSingleTouch = false
            onEnded?()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isTrackingSingleTouch {
            isTrackingSingleTouch = false
            onEnded?()
        }
    }
}
