import AppKit
import PingScopeCore
import SwiftUI

struct NetworkDiagnosisRow: View {
    let diagnosis: NetworkPerspectiveDiagnosis

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(diagnosis.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if diagnosis.confidence == .tentative {
                        Text("Tentative")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(diagnosis.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let evidenceNote = diagnosis.evidenceNote {
                    Text(evidenceNote)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.82))
                        .lineLimit(1)
                }
                if !diagnosis.tierEvidence.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(diagnosis.tierEvidence, id: \.tier) { evidence in
                            NetworkTierEvidenceChip(evidence: evidence, isFault: diagnosis.faultTier == evidence.tier)
                        }
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(chainAccessibilityText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        switch diagnosis.scope {
        case .noData: "circle"
        case .allReachable: "checkmark.circle.fill"
        case .localNetwork: "network.slash"
        case .upstream: "wifi.exclamationmark"
        case .remoteService: "exclamationmark.triangle.fill"
        case .partialDegradation: "speedometer"
        }
    }

    private var tint: Color {
        switch diagnosis.scope {
        case .noData: .secondary
        case .allReachable: .green
        case .localNetwork: .red
        case .upstream: .orange
        case .remoteService: .yellow
        case .partialDegradation: .yellow
        }
    }

    private var accessibilityText: String {
        var parts = [diagnosis.title, diagnosis.detail]
        if diagnosis.confidence == .tentative {
            parts.append(diagnosis.confidence.displayName)
        }
        if let evidenceNote = diagnosis.evidenceNote {
            parts.append(evidenceNote)
        }
        if !diagnosis.tierEvidence.isEmpty {
            parts.append(chainAccessibilityText)
        }
        return parts.joined(separator: ". ")
    }

    private var chainAccessibilityText: String {
        diagnosis.tierEvidence
            .map { "\($0.tier.shortName): \($0.summary)" }
            .joined(separator: ", ")
    }
}

private struct NetworkTierEvidenceChip: View {
    let evidence: NetworkPerspectiveDiagnosis.TierEvidence
    let isFault: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(statusColor: evidence.status.statusColor))
                .frame(width: 6, height: 6)
            Text(evidence.tier.shortName)
                .lineLimit(1)
            Text("\(evidence.healthyCount)/\(evidence.totalCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption2.weight(isFault ? .bold : .semibold))
        .foregroundStyle(isFault ? .primary : .secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(statusColor: evidence.status.statusColor).opacity(isFault ? 0.18 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(statusColor: evidence.status.statusColor).opacity(isFault ? 0.42 : 0.16), lineWidth: 1)
        )
        .help("\(evidence.tier.settingsName): \(evidence.summary)")
    }
}

