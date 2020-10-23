import Vapor

public struct CarrierResponse: Content {

    public enum CarrierType: String, Codable {
        case mobile
        case landline
        case voip
    }

    public let name: String
    public let type: CarrierType
}
