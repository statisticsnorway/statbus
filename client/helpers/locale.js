import { connect } from 'react-redux'
import { momentLocale } from 'helpers/dateHelper'

// TODO: should be configurable
export const locales = [
  { key: 'en-GB', text: 'English', flag: 'gb' },
  { key: 'ky-KG', text: 'Кыргызча', flag: 'kg' },
  { key: 'ru-RU', text: 'Русский', flag: 'ru' },
]

export const getText = (locale) => {
  // eslint-disable-next-line no-underscore-dangle
  const f = key => window.__initialStateFromServer.allLocales[locale][key] || `"${key}"`
  f.lang = locale
  momentLocale(f.lang)
  return f
}

// TODO: remove wrapper and connect explicitly
export const wrapper = component => connect(
  ({ locale }, ownProps) =>
  ({ ...ownProps, localize: getText(locale) }),
)(component)
