import { connect } from 'react-redux'
import { shouldUpdate } from 'recompose'
import { pipe } from 'ramda'

import { setMomentLocale } from 'helpers/dateHelper'
import config from 'helpers/config'
import { hasValue } from './validation'

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

export const getNewName = (
  { name, code, nameLanguage1, nameLanguage2, fullPath, fullPathLanguage1, fullPathLanguage2 },
  isUsersPage,
) => {
  const locale = getLocale()

  let newName = ''
  if (locale === 'en-GB') {
    if (hasValue(nameLanguage1)) {
      newName = nameLanguage1
    }
    if (hasValue(fullPathLanguage1)) {
      newName = fullPathLanguage1
    }
  } else if (locale === 'ky-KG') {
    if (hasValue(nameLanguage2)) {
      newName = nameLanguage2
    }
    if (hasValue(fullPathLanguage2)) {
      newName = fullPathLanguage2
    }
  } else if (locale === 'ru-RU') {
    if (hasValue(name)) {
      newName = name
    }
    if (hasValue(fullPath)) {
      newName = fullPath
    }
  }

  if (hasValue(code) && isUsersPage === undefined) {
    return `${code} ${newName}`
  }
  return newName
}
