import Darwin
import Foundation

enum NetworkAddresses {
    static func read(interface: String) -> (ipv4: String?, ipv6: String?) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (nil, nil) }
        defer { freeifaddrs(list) }
        var ipv4: String?
        var ipv6: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == interface,
                  let address = entry.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                              socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if family == AF_INET { ipv4 = ipv4 ?? text }
            if family == AF_INET6, !text.lowercased().hasPrefix("fe80:") { ipv6 = ipv6 ?? text }
        }
        return (ipv4, ipv6)
    }
}
