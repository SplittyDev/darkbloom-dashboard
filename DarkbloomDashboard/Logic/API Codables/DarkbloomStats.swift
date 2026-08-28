import Foundation

struct DarkbloomStats: Decodable {
    let activeProviders: Int
    let providers: [DarkbloomProviderStat]
    
    let totalBandwidthGbs: Double
    let totalCpuCores: Int
    let totalGpuCores: Int
    let totalMemoryGb: Int
    let totalRequests: Int
    
    let totalTokens: Int
    let totalPromptTokens: Int
    let totalCompletionTokens: Int
    
    let providerLocations: [DarkbloomProviderLocation]
    let requestFlows: [DarkbloomRequestFlow]
    let requestLocations: [DarkbloomRequestLocation]
    let requestRegions: [DarkbloomRequestRegion]
    let timeSeries: [DarkbloomTimeSeriesEntry]
}
