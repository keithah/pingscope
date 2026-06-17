import Foundation
import PingScopeCore

struct ProbeCase {
    var name: String
    var host: HostConfig
    var expectedNote: String
}

@main
struct ProbeValidate {
    static func main() async {
        let cases = [
            ProbeCase(
                name: "TCP",
                host: HostConfig(
                    displayName: "TCP Cloudflare",
                    address: "1.1.1.1",
                    method: .tcp,
                    port: 443,
                    timeout: .seconds(3)
                ),
                expectedNote: "fresh TCP connection"
            ),
            ProbeCase(
                name: "UDP",
                host: HostConfig(
                    displayName: "UDP Cloudflare DNS",
                    address: "1.1.1.1",
                    method: .udp,
                    port: 53,
                    timeout: .seconds(3)
                ),
                expectedNote: "UDP datagram send path"
            ),
            ProbeCase(
                name: "ICMP",
                host: HostConfig(
                    displayName: "ICMP Cloudflare",
                    address: "1.1.1.1",
                    method: .icmp,
                    port: nil,
                    timeout: .seconds(3)
                ),
                expectedNote: "/sbin/ping"
            )
        ]

        let tester = HostTester(probeFactory: DefaultProbeFactory(flavor: .developerID))
        var failures = 0

        for probeCase in cases {
            let result = await tester.test(probeCase.host)
            if result.isSuccess {
                print("PASS \(probeCase.name): \(formatLatency(result.latency)) \(result.metadata.note ?? probeCase.expectedNote)")
            } else {
                failures += 1
                let reason = result.failureReason?.userMessage ?? "Unknown failure"
                print("FAIL \(probeCase.name): \(reason) \(result.metadata.note ?? "")")
            }
        }

        if failures > 0 {
            print("Probe validation failed: \(failures) failure(s).")
            exit(1)
        }

        print("Probe validation passed. UDP validates datagram send/readiness, not an echoed UDP round trip.")
    }

    private static func formatLatency(_ duration: Duration?) -> String {
        guard let duration else { return "--ms" }
        let components = duration.components
        let milliseconds = (Double(components.seconds) * 1_000.0)
            + (Double(components.attoseconds) / 1_000_000_000_000_000.0)
        return "\(Int(milliseconds.rounded()))ms"
    }
}
