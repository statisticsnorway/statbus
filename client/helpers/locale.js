import { connect } from 'react-redux'

const actionType = 'SET_LOCALE'

export const actionCreator = locale => ({
  type: actionType,
  data: { locale },
})

export const reducer = (state = 'en-GB', action) => action.type === actionType
  ? action.data.locale
  : state

export const locales = [
  { key: 'en-GB', text: 'English', flag: 'gb' },
  { key: 'ky-KG', text: 'Кыргызча', flag: 'kg' },
  { key: 'ru-RU', text: 'Русский', flag: 'ru' },
]

// eslint-disable-next-line no-underscore-dangle, max-len
const getText = locale => key => window.__initialStateFromServer.allLocales[locale][key]
  || 'CASH RULEZ EVERYTHING AROUND ME: C.R.E.A.M, GET THE MONEY. DOLLAR, DOLLAR BILL YA\'LL!'

export const wrapper = component => connect(
  ({ locale }, ownProps) => ({ ...ownProps, localize: getText(locale) }),
)(component)
