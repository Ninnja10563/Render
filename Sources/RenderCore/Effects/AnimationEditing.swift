import Foundation

/// Addresses a curve without coupling animation editing to the inspector or renderer.
public enum AnimationTarget: Hashable, Sendable {
    case property(String)
    case effect(UUID)

    public func curve(in clip: TimelineClip) throws -> AnimationCurve {
        switch self {
        case .property(let name):
            guard ["x", "y", "scale", "rotation", "opacity", "volume"].contains(name) else {
                throw RenderError.invalid("This property cannot be animated.")
            }
            return clip.properties.animations[name] ?? AnimationCurve()
        case .effect(let id):
            guard let effect = clip.effects.first(where: { $0.id == id }) else { throw RenderError.invalid("Effect no longer exists.") }
            return effect.animation
        }
    }
    public func value(in clip: TimelineClip, at frame: Int64) throws -> Double {
        switch self {
        case .property(let name): return try curve(in: clip).value(at: Double(frame), fallback: clip.properties.value(name, at: Double(frame)))
        case .effect(let id):
            guard let effect = clip.effects.first(where: { $0.id == id }) else { throw RenderError.invalid("Effect no longer exists.") }
            return effect.animation.value(at: Double(frame), fallback: effect.amount)
        }
    }
    public func replacingCurve(in clip: inout TimelineClip, with curve: AnimationCurve) throws {
        _ = try self.curve(in: clip)
        switch self {
        case .property(let name): clip.properties.animations[name] = curve
        case .effect(let id):
            guard let index = clip.effects.firstIndex(where: { $0.id == id }) else { throw RenderError.invalid("Effect no longer exists.") }
            clip.effects[index].animation = curve
        }
    }
}

public enum AnimationEdit: Sendable {
    /// Updating an existing key preserves its identity and outgoing interpolation.
    case set(frame: Int64, value: Double)
    case remove(Set<UUID>)
    case move(key: UUID, to: Int64)
    case interpolation(Set<UUID>, Interpolation)
    /// Frames in the payload are offsets from its first key; collisions replace destination keys.
    case paste([Keyframe], at: Int64)

    public func applying(to original: AnimationCurve) throws -> AnimationCurve {
        var curve = original
        func checkFrame(_ frame: Int64) throws {
            guard (0..<200_000_000).contains(frame) else { throw RenderError.invalid("Keyframe is outside animation bounds.") }
        }
        switch self {
        case .set(let frame, let value):
            try checkFrame(frame)
            guard value.isFinite else { throw RenderError.invalid("Keyframe value must be finite.") }
            var key = curve.keys.first(where: { $0.frame == frame }) ?? Keyframe(frame: frame, value: value)
            key.value = value; curve.set(key)
        case .remove(let ids): curve.keys.removeAll { ids.contains($0.id) }
        case .move(let id, let frame):
            try checkFrame(frame)
            guard var key = curve.keys.first(where: { $0.id == id }) else { throw RenderError.invalid("Keyframe no longer exists.") }
            guard !curve.keys.contains(where: { $0.id != id && $0.frame == frame }) else { throw RenderError.invalid("There is already a keyframe at that position.") }
            key.frame = frame; curve.set(key)
        case .interpolation(let ids, let interpolation):
            for index in curve.keys.indices where ids.contains(curve.keys[index].id) { curve.keys[index].interpolation = interpolation }
        case .paste(let keys, let frame):
            try checkFrame(frame)
            guard let origin = keys.map(\.frame).min() else { return curve }
            guard origin >= 0, keys.allSatisfy({ $0.frame < 200_000_000 && $0.value.isFinite }), Set(keys.map(\.frame)).count == keys.count else {
                throw RenderError.invalid("Invalid keyframe clipboard.")
            }
            for key in keys {
                let destination = frame + key.frame - origin
                try checkFrame(destination)
                curve.set(Keyframe(frame: destination, value: key.value, interpolation: key.interpolation))
            }
        }
        return curve
    }
}
