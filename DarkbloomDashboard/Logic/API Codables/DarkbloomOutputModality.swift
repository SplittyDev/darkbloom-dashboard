import Foundation

enum DarkbloomOutputModality: String, Decodable {
    case text = "text"
    case image = "image"
    case audio = "audio"
    case embeddings = "embeddings"
}
