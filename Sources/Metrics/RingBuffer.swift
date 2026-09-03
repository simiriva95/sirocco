/// Fixed-capacity circular buffer. Never grows: the app runs for weeks and every
/// time series must have a hard memory ceiling.
struct RingBuffer<Element>: Sendable where Element: Sendable {
    private var storage: [Element?]
    private var head = 0      // index of the next write
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Oldest → newest.
    var elements: [Element] {
        guard count > 0 else { return [] }
        let start = (head - count + capacity) % capacity
        return (0..<count).map { storage[(start + $0) % capacity]! }
    }

    var last: Element? {
        guard count > 0 else { return nil }
        return storage[(head - 1 + capacity) % capacity]
    }

    var isFull: Bool { count == capacity }
}
