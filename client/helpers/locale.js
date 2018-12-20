import { connect } from 'react-redux'
import { shouldUpdate } from 'recompose'
import { pipe } from 'ramda'

import { setMomentLocale } from 'helpers/dateHelper'
import config from 'helpers/config'

export const setLocale = value => window.localStorage.setItem('locale', value)
export const getLocale = () => window.localStorage.getItem('locale') || config.defaultLocale

export const getFlag = locale => locale.substr(-2).toLowerCase()

export const getText = (locale) => {
  const dict = config.resources[locale]
  const getWord = (key) => {
    if (dict[key] !== undefined) return dict[key]
    if (typeof key === 'string' && key.endsWith('IsRequired')) {
      return `${getWord(key.split('IsRequired')[0])} ${dict.IsRequired}`
    }
    if (process.env.NODE_ENV === 'development') return `"${key}"`
    return key
  }
  // TODO: remove this hack, pass selected locale to components
  // and use this helper in component directly every time
  // instead of passing a function in mapStateToProps
  getWord.lang = locale
  setMomentLocale(getWord.lang)
  return getWord
}

const ifLocaleChanged = (prev, next) => prev.localize.lang !== next.localize.lang

const stateToProps = (state, props) => ({
  ...props,
  localize: getText(state.locale),
})

export const withLocalize = pipe(shouldUpdate(ifLocaleChanged), connect(stateToProps))

export const withLocalizeNaive = connect(stateToProps)

export const getNewName = (item, isUsersPage) => {
  const locale = getLocale()
  const { defaultLocale } = config

  let newName = ''
  let language = ''
  if (locale === 'en-GB') {
    language = 'Language1'
  } else if (locale === 'ky-KG') {
    language = 'Language2'
  }

  const fullPath = `fullPath${language}`
  const name = `name${language}`
  if (fullPath in item) {
    newName = item[fullPath]
  } else if (name in item) {
    newName = item[name]
  }

  if ('code' in item && isUsersPage === undefined) {
    return `${item.code || ''} ${newName || ''}`
  }

  if (defaultLocale === locale) {
    newName = item.name
  }

  return newName
}
