import Foundation

public extension Array {
    func chunked(into size: Int) -> [Array<Element>] {
        guard size > 0, isEmpty == false else {
            return isEmpty ? [] : [self]
        }

        var chunks = [Array<Element>]()
        chunks.reserveCapacity((count + size - 1) / size)

        var index = startIndex
        while index < endIndex {
            let end = Swift.min(index + size, endIndex)
            chunks.append(Array(self[index..<end]))
            index = end
        }

        return chunks
    }
}
