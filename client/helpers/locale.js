import { connect } from 'react-redux'
import { shouldUpdate } from 'recompose'
import { pipe } from 'ramda'

import { momentLocale } from 'helpers/dateHelper'
import config from 'helpers/config'

export const setLocale = value => window.localStorage.setItem('locale', value)
export const getLocale = () => window.localStorage.getItem('locale') || config.defaultLocale

export const getFlag = locale => locale.substr(-2).toLowerCase()

export const getText = (locale) => {
  const f = key => config.resources[locale][key] || (
    process.env.NODE_ENV === 'development'
      ? `"${key}"`
      : key
  )
  // TODO: remove this hack, pass selected locale to components
  // and use this helper in component directly every time
  // instead of passing a function in mapStateToProps
  f.lang = locale
  momentLocale(f.lang)
  return f
}

const ifLocaleChanged = (prev, next) => prev.localize.lang !== next.localize.lang

const mapStateToProps = (state, props) => ({
  ...props,
  localize: getText(state.locale),
})

export const withLocalize = pipe(
  shouldUpdate(ifLocaleChanged),
  connect(mapStateToProps),
)

export const withLocalizeNaive = connect(mapStateToProps)
