public protocol Resource {
    @MainActor
    mutating func destroy()
}
