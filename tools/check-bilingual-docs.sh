#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

pairs=(
  "README.md:README.zh-CN.md"
  "ARCHITECTURE.md:ARCHITECTURE.zh-CN.md"
  "ROADMAP.md:ROADMAP.zh-CN.md"
  "SECURITY.md:SECURITY.zh-CN.md"
  "CONTRIBUTING.md:CONTRIBUTING.zh-CN.md"
  "AndroidReceiver/README.md:AndroidReceiver/README.zh-CN.md"
  "docs/README.md:docs/README.zh-CN.md"
  "docs/120hz-migration-plan.md:docs/120hz-migration-plan.zh-CN.md"
  "docs/automatic-updates.md:docs/automatic-updates.zh-CN.md"
  "docs/android-connection-generation.md:docs/android-connection-generation.zh-CN.md"
  "docs/android-binary-frame-header-v2.md:docs/android-binary-frame-header-v2.zh-CN.md"
  "docs/android-decoder-low-latency.md:docs/android-decoder-low-latency.zh-CN.md"
  "docs/android-drop-reason-policy.md:docs/android-drop-reason-policy.zh-CN.md"
  "docs/android-protocol-v2-negotiation.md:docs/android-protocol-v2-negotiation.zh-CN.md"
  "docs/android-stability-latency-audit.md:docs/android-stability-latency-audit.zh-CN.md"
  "docs/android-wifi-low-latency-surface-frame-rate.md:docs/android-wifi-low-latency-surface-frame-rate.zh-CN.md"
  "docs/brand-assets.md:docs/brand-assets.zh-CN.md"
  "docs/branding-and-doc-audit.md:docs/branding-and-doc-audit.zh-CN.md"
  "docs/benchmark-guide.md:docs/benchmark-guide.zh-CN.md"
  "docs/development-preview.md:docs/development-preview.zh-CN.md"
  "docs/frame-size-negotiation.md:docs/frame-size-negotiation.zh-CN.md"
  "docs/latency-measurement.md:docs/latency-measurement.zh-CN.md"
  "docs/mac-local-fast-congestion-decrease.md:docs/mac-local-fast-congestion-decrease.zh-CN.md"
  "docs/performance-metrics-audit.md:docs/performance-metrics-audit.zh-CN.md"
  "docs/release-checklist.md:docs/release-checklist.zh-CN.md"
  "docs/release-notes-v0.2.0-preview.1.md:docs/release-notes-v0.2.0-preview.1.zh-CN.md"
  "docs/release-notes-v0.2.0-preview.2.md:docs/release-notes-v0.2.0-preview.2.zh-CN.md"
  "docs/release-notes-v0.2.0-preview.3.md:docs/release-notes-v0.2.0-preview.3.zh-CN.md"
  "docs/release-notes-preview-0.1.md:docs/release-notes-preview-0.1.zh-CN.md"
  "docs/roadmap-and-acceptance.md:docs/roadmap-and-acceptance.zh-CN.md"
  "docs/stability-test-report.md:docs/stability-test-report.zh-CN.md"
  "docs/usb-vs-wifi-benchmark.md:docs/usb-vs-wifi-benchmark.zh-CN.md"
)

failures=0
for pair in "${pairs[@]}"; do
  english="${pair%%:*}"
  chinese="${pair#*:}"
  for file in "$english" "$chinese"; do
    if [[ ! -f "$file" ]]; then
      echo "missing bilingual document: $file" >&2
      failures=$((failures + 1))
    fi
  done
  if [[ -f "$english" ]] && ! grep -Fq "简体中文" "$english"; then
    echo "missing Chinese language link: $english" >&2
    failures=$((failures + 1))
  fi
  if [[ -f "$chinese" ]] && ! grep -Fq "English" "$chinese"; then
    echo "missing English language link: $chinese" >&2
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  echo "bilingual documentation check failed: $failures issue(s)" >&2
  exit 1
fi

echo "bilingual documentation check passed: ${#pairs[@]} pairs"
