import Foundation

struct DarkbloomModelData: Decodable, Identifiable {
    let id: String
    let object: String
    
    let created: Int
    let ownedBy: String
    
    let name: String
    let description: String?
    let huggingFaceId: String?
    let metadata: DarkbloomModelMetadata
    
    let contextLength: Int
    let maxOutputLength: Int
    
    let inputModalities: [DarkbloomInputModality]
    let outputModalities: [DarkbloomOutputModality]
    
    let supportedFeatures: [String]?
    let supportedSamplingParameters: [String]?
    
    let pricing: DarkbloomModelPricing
    
    var model: DarkbloomModel {
        DarkbloomModel(rawValue: id)
    }
}
