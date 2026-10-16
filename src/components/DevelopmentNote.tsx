import type { Locale } from "../content"

export default function DevelopmentNote({ locale }: { locale: Locale }) {
  const chinese = locale === "zh"
  return (
    <aside
      className="development-note"
      aria-label={chinese ? "新增实验功能" : "Experimental features"}
    >
      <div className="shell development-layout">
        <div>
          <span className="section-label">
            {chinese ? "v0.2.1-p7 实验功能" : "Experimental in v0.2.1-p7"}
          </span>
          <h2>
            {chinese
              ? "两台 Mac，也能互相连接。"
              : "Connect one Mac to another."}
          </h2>
          <p>
            {chinese
              ? "任一 Mac 可发送或接收，每次单向扩展或镜像，支持同一局域网的 Wi-Fi 与以太网。发布包包含硬件 HEVC／H.264 回退与固定接口直连；双机性能、真实 Pencil 与长时稳定性仍待验证。"
              : "Either Mac can send or receive a one-way extended or mirrored display over local Wi-Fi or Ethernet. The downloads include hardware HEVC/H.264 fallback and pinned direct links; two-Mac performance, real Pencil and endurance validation remain pending."}
          </p>
        </div>
        <a
          className="text-link"
          href={`https://github.com/chenyuhao0628/displayweave/blob/main/docs/mac-to-mac${chinese ? ".zh-CN" : ""}.md`}
        >
          {chinese ? "查看连接与验收指南" : "Connection and acceptance guide"}
          <span aria-hidden="true">↗</span>
        </a>
      </div>
    </aside>
  )
}
