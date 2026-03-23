import Foundation

actor SVGACacheStore {
    static let shared = SVGACacheStore()

    private let strongCache = NSCache<NSString, SVGAVideoEntity>()
    private let weakCache = NSMapTable<NSString, SVGAVideoEntity>(
        keyOptions: .strongMemory,
        valueOptions: .weakMemory
    )

    func read(key: String) -> SVGAVideoEntity? {
        let k = key as NSString
        return strongCache.object(forKey: k) ?? weakCache.object(forKey: k)
    }

    func save(key: String, entity: SVGAVideoEntity) {
        strongCache.setObject(entity, forKey: key as NSString)
    }

    func saveWeak(key: String, entity: SVGAVideoEntity) {
        weakCache.setObject(entity, forKey: key as NSString)
    }
}
