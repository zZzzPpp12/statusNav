import Darwin
import Foundation
import StatusNavCore

enum TrafficReader {
    static func read(interface: String) -> TrafficSample? {
        var query: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&query, u_int(query.count), nil, &size, nil, 0) == 0, size > 0, size < 8_000_000 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let status = bytes.withUnsafeMutableBytes { sysctl(&query, u_int(query.count), $0.baseAddress, &size, nil, 0) }
        guard status == 0 else { return nil }
        return bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset + 4 <= size {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { return nil }
                if Int32(bytes[offset + 3]) == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        let text = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        if text == interface {
                            return TrafficSample(interface: interface, received: message.ifm_data.ifi_ibytes,
                                                 sent: message.ifm_data.ifi_obytes, uptime: ProcessInfo.processInfo.systemUptime)
                        }
                    }
                }
                offset += length
            }
            return nil
        }
    }
}
