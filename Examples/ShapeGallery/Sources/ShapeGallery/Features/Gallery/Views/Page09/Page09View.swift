import SwiftUI

// Page 9: filters. SVG filter primitives have no SwiftUI counterpart; blur, shadow,
// colour and blend effects use the nearest view modifiers, and the primitives with
// no equivalent are drawn as the picture they make.
struct Page09View: View {
    var body: some View {
        FixtureGrid {
            FxBlur()
            FxShadow()
            FxShadowScaled()
            FxMaskGradient()
            FxDropShadowCss()
            FxHugeRegion()
            FxMatrix()
            FxBlend()
            FxBoxFilter()
            FxImageFilter()
            FxCss()
            FxShapeOps()
            FxNoise()
            FxLight()
        }
    }
}
