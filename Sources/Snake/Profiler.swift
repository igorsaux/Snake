private let MAX_MEASUREMENTS = 10

public final class ProfilerGroup {
    private var _measurements: [Duration] = []
    private var _idx: Int = 0

    public init() {
        self._measurements.reserveCapacity(MAX_MEASUREMENTS)

        for _ in 0..<MAX_MEASUREMENTS {
            self._measurements.append(Duration.zero)
        }
    }

    public func measure(_ work: () throws -> Void) rethrows {
        let sw = ContinuousClock()
        let duration = try sw.measure {
            try work()
        }

        self._measurements[self._idx] = duration
        self._idx = (self._idx + 1) % MAX_MEASUREMENTS
    }

    public func avg() -> Duration {
        return self._measurements.reduce(Duration.zero) { $0 + $1 }
            / Double(self._measurements.count)
    }
}

public final class Profiler {
    private var _groups: [String: ProfilerGroup] = [:]

    public func group(_ name: String) -> ProfilerGroup {
        if let group = self._groups[name] {
            return group
        } else {
            let group = ProfilerGroup()
            self._groups[name] = group

            return group
        }
    }

    @discardableResult
    public func measure(_ group: String, _ work: () throws -> Void) rethrows -> ProfilerGroup {
        let group = self.group(group)

        try group.measure(work)

        return group
    }

    public func clear() {
        self._groups.removeAll()
    }
}
