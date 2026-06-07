import Foundation
import MetricKit
import os

@MainActor
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    func register() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let begin = payload.timeStampBegin.description
            let end = payload.timeStampEnd.description
            AppLog.diagnostics.notice("metric payload \(begin, privacy: .public) -> \(end, privacy: .public)")
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let crashes = payload.crashDiagnostics {
                for crash in crashes {
                    let exceptionType = crash.exceptionType?.intValue ?? 0
                    let signal = crash.signal?.intValue ?? 0
                    let virt = crash.virtualMemoryRegionInfo ?? "n/a"
                    AppLog.diagnostics.fault("crash: \(exceptionType, privacy: .public) signal=\(signal, privacy: .public) virt=\(virt, privacy: .public)")
                }
            }
            if let hangs = payload.hangDiagnostics {
                for hang in hangs {
                    AppLog.diagnostics.error("hang: duration=\(hang.hangDuration.value, privacy: .public)\(hang.hangDuration.unit.symbol, privacy: .public)")
                }
            }
            if let cpu = payload.cpuExceptionDiagnostics {
                for ex in cpu {
                    AppLog.diagnostics.error("cpu exception: total=\(ex.totalCPUTime.value, privacy: .public)\(ex.totalCPUTime.unit.symbol, privacy: .public)")
                }
            }
        }
    }
}
