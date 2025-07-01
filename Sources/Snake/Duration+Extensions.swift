extension Duration {
    public func sec() -> Double {
        return Double(self.components.seconds) + Double(self.components.attoseconds) * 1e-18
    }

    public func ms() -> Double {
        return Double(self.components.seconds) * 1000.0 + Double(self.components.attoseconds)
            * 1e-15
    }
}
