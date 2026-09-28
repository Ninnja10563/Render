import Foundation

extension TimelineClip {
    /// Preserve the old animation phase when revealing leading handles. If the new local
    /// origin would be negative, translate every animation/fade together into valid coordinates.
    mutating func moveAnimationOrigin(by delta: Int64) {
        let next = animationOffset + delta
        if next >= 0 { animationOffset = next; return }
        let shift = -next
        animationOffset = 0
        for name in Array(properties.animations.keys) {
            guard var curve = properties.animations[name] else { continue }
            for index in curve.keys.indices { curve.keys[index].frame += shift }
            properties.animations[name] = curve
        }
        for index in effects.indices {
            for key in effects[index].animation.keys.indices { effects[index].animation.keys[key].frame += shift }
        }
        if var fades = properties.audioFades { fades.start += shift; fades.end += shift; properties.audioFades = fades }
    }
}
