import type { Locale } from "../content"

export default function DevelopmentNote({ locale }: { locale: Locale }) {
  const chinese = locale === "zh"
  return (
    <aside
      className="development-note"
      aria-label={chinese ? "源码开发进展" : "Source development"}
    >
      <div className="shell development-layout">
        <div>
          <span className="section-label">
            {chinese ? "源码开发版" : "Source build"}
          </span>
          <h2>
            {chinese
              ? "两台 Mac，也能互相连接。"
              : "Connect one Mac to another."}
          </h2>
          <p>
            {chinese
              ? "任一 Mac 可发送或接收，每次单向扩展或镜像，支持同一局域网的 Wi-Fi 与以太网。该功能尚未包含在下方发布包中；双机性能与长时稳定性仍待验证。"
              : "Either Mac can send or receive a one-way extended or mirrored display over local Wi-Fi or Ethernet. This source feature is not in the downloads below; two-Mac performance and endurance validation remain pending."}
          </p>
        </div>
        <a
          className="text-link"
          href={`https://github.com/chenyuhao0628/displayweave/blob/main/docs/mac-to-mac${chinese ? ".zh-CN" : ""}.md`}
        >
          {chinese ? "查看构建与连接指南" : "Build and connection guide"}
          <span aria-hidden="true">↗</span>
        </a>
      </div>
    </aside>
  )
}
