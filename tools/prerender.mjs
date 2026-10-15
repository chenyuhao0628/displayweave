// Build both crawlable routes from the same React tree used for hydration.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import { render } from '../dist-ssr/entry-server.js'

const source = await fs.readFile('site-dist/index.html', 'utf8')
assert.ok(source.includes('<div id="root"></div>'), 'prerender: missing root')
const base = 'https://chenyuhao0628.github.io/displayweave/'
const chineseDescription = 'DisplayWeave 将 iPhone、iPad 和 Android 用作 Mac 的本地第二屏，支持 Apple USB/局域网、Android ADB USB/局域网及经过校验的应用更新。'

function meta(html, attribute, name, value) {
  const pattern = new RegExp(`(<meta ${attribute}="${name}" content=")[^"]*("[^>]*>)`)
  assert.match(html, pattern, `missing metadata: ${name}`)
  return html.replace(pattern, (_, before, after) => before + value + after)
}

for (const locale of ['en', 'zh']) {
  let html = source.replace('<div id="root"></div>', `<div id="root">${render(locale)}</div>`)
  if (locale === 'zh') {
    const title = 'DisplayWeave — 将闲置设备用作 Mac 第二屏'
    html = html.replace('<html lang="en">', '<html lang="zh-CN">')
      .replace(/<title>.*?<\/title>/, `<title>${title}</title>`)
      .replace(/(<link rel="canonical" href=")[^"]*("[^>]*>)/,
        (_, before, after) => before + base + 'zh.html' + after)
    for (const [attr, name, value] of [
      ['name', 'description', chineseDescription],
      ['property', 'og:locale', 'zh_CN'],
      ['property', 'og:locale:alternate', 'en_US'],
      ['property', 'og:title', title],
      ['property', 'og:description', chineseDescription],
      ['property', 'og:url', base + 'zh.html'],
      ['name', 'twitter:title', title],
      ['name', 'twitter:description', chineseDescription],
    ]) html = meta(html, attr, name, value)
    html = html.replace(/(<script type="application\/ld\+json">)([\s\S]*?)(<\/script>)/,
      (_, before, data, after) => {
        const schema = JSON.parse(data)
        schema.description = chineseDescription
        schema.url = base + 'zh.html'
        return before + JSON.stringify(schema) + after
      })
  }
  await fs.writeFile(`site-dist/${locale === 'zh' ? 'zh' : 'index'}.html`, html)
}
console.log('Prerendered English and Chinese routes with hydration boundaries')
