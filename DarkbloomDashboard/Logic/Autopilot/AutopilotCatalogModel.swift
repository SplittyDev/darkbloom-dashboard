import Foundation

/// The provider catalog identifies actual serving artifacts. Unlike /v1/models pricing,
/// these IDs match `models list` and CLI selections, so no name-based aliases are inferred.
struct AutopilotCatalogModel: Decodable, Sendable {
    let id: String
    let active: Bool
    let modelType: String
    let minRamGb: Double?

    static func exclusions(local: [AutopilotLocalModel], catalog: [Self], memoryGB: Double) -> [String: String] {
        var result: [String: String] = [:]
        for model in local {
            let matches = catalog.filter { $0.id == model.id }
            guard matches.count == 1, let entry = matches.first else {
                result[model.id] = matches.isEmpty ? "Not in the Darkbloom model catalog" : "Ambiguous Darkbloom catalog entry"
                continue
            }
            guard entry.active else {
                result[model.id] = "Inactive in the Darkbloom model catalog"
                continue
            }
            guard entry.modelType == "text" else {
                result[model.id] = "Catalog model does not support text inference benchmarking"
                continue
            }
            if let required = entry.minRamGb {
                guard required.isFinite, required > 0, required <= memoryGB else {
                    result[model.id] = "Does not meet the catalog minimum RAM requirement (\(required.formatted()) GB)"
                    continue
                }
            }
            if let reason = model.exclusion(memoryGB: memoryGB) { result[model.id] = reason }
        }
        return result
    }
}
