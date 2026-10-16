import type { Locale } from "./content"

export function localeForPathname(pathname: string): Locale {
  return /\/zh(?:\.html)?\/?$/.test(pathname) ? "zh" : "en"
}
