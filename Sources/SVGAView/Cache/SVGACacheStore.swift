import Foundation

/// 保存已解析 SVGA 动画实体的内存缓存。
///
/// 缓存同时维护强引用和弱引用两种存储方式，用于支持解析器的可配置缓存策略。
actor SVGACacheStore {
    /// 共享缓存实例。
    static let shared = SVGACacheStore()

    private let strongCache = NSCache<NSString, SVGA.VideoEntity>()
    private let weakCache = NSMapTable<NSString, SVGA.VideoEntity>(
        keyOptions: .strongMemory,
        valueOptions: .weakMemory
    )

    /// 读取指定 key 对应的动画实体。
    ///
    /// - Parameter key: 缓存 key。
    /// - Returns: 命中缓存时返回动画实体，否则返回 `nil`。
    func read(key: String) -> SVGA.VideoEntity? {
        let k = key as NSString
        return strongCache.object(forKey: k) ?? weakCache.object(forKey: k)
    }

    /// 保存动画实体到强引用缓存。
    ///
    /// - Parameters:
    ///   - key: 缓存 key。
    ///   - entity: 要缓存的动画实体。
    func save(key: String, entity: SVGA.VideoEntity) {
        strongCache.setObject(entity, forKey: key as NSString)
    }

    /// 保存动画实体到弱引用缓存。
    ///
    /// - Parameters:
    ///   - key: 缓存 key。
    ///   - entity: 要缓存的动画实体。
    func saveWeak(key: String, entity: SVGA.VideoEntity) {
        weakCache.setObject(entity, forKey: key as NSString)
    }
}
