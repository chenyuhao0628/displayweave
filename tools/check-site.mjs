import assert from 'node:assert/strict'
import { access, readFile } from 'node:fs/promises'
import path from 'node:path'
import { localeForPathname } from '../build/site/ssr/entry-server.js'

// Pages strips .html; initial client rendering must retain the SSR language.
for (const pathname of ['/zh.html', '/zh', '/displayweave/zh.html', '/displayweave/zh', '/displayweave/zh/']) {
  assert.equal(localeForPathname(pathname), 'zh', `${pathname}: Chinese after canonical redirect`)
}
for (const pathname of ['/', '/displayweave/', '/displayweave/index.html', '/displayweave/not-zh']) {
  assert.equal(localeForPathname(pathname), 'en', `${pathname}: English route`)
}

for (const [file, locale] of [['index.html', 'en'], ['zh.html', 'zh-CN']]) {
  const html = await readFile(`build/site/client/${file}`, 'utf8')
  assert.ok(html.includes(`<html lang="${locale}">`), `${file}: document language`)
  const title = html.match(/<title>(.*?)<\/title>/)?.[1] ?? ''
  assert.ok(title.includes('DisplayWeave'), `${file}: branded title`)
  if (locale === 'zh-CN') assert.match(title, /[\u4e00-\u9fff]/u, 'Chinese route needs a Chinese title')
  for (const language of ['en', 'zh-CN', 'x-default']) {
    assert.equal((html.match(new RegExp(`hreflang="${language}"`, 'g')) ?? []).length, 1,
      `${file}: one alternate per language`)
  }
  assert.equal((html.match(/rel="canonical"/g) ?? []).length, 1, `${file}: single canonical`)
  const path = locale === 'zh-CN' ? 'zh.html' : ''
  assert.ok(html.includes(`rel="canonical" href="https://chenyuhao0628.github.io/displayweave/${path}"`))
  assert.ok(html.includes('<main') && html.includes('<h1'), `${file}: prerendered content`)
  for (const anchor of ['download', 'status', 'transport', 'evidence', 'trust', 'faq']) {
    assert.ok(html.includes(`id="${anchor}"`), `${file}: reachable ${anchor} navigation`)
  }
  assert.ok(html.includes(locale === 'en' ? 'Experimental in v0.3.3' : 'v0.3.3 实验功能'),
    `${file}: published experimental capability is labeled`)
}
// Validate the actual built files after relocation, including static bilingual pages.
const siteRoot = path.resolve('build/site/client')
for (const file of ['index.html', 'zh.html', 'privacy.html', 'privacy.zh-CN.html']) {
  const html = await readFile(path.join(siteRoot, file), 'utf8')
  for (const [, url] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    if (/^(?:[a-z][\w+.-]*:|\/\/|#)/i.test(url)) continue
    const target = path.resolve(siteRoot, url.split(/[?#]/)[0] || file)
    assert.ok(target === siteRoot || target.startsWith(siteRoot + path.sep), `${file}: local link stays in site`)
    await access(target)
  }
}
console.log('Bilingual site metadata, navigation and release-scope checks PASS')
