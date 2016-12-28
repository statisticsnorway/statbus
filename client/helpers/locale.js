import { connect } from 'react-redux'
import { format } from 'date-fns'

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
export const getText = (locale, key) => window.__initialStateFromServer.allLocales[locale][key]

export const wrapper = component => connect(
  ({ locale }, ownProps) => ({ ...ownProps, locale }),
)(component)

export const dateTimeFormat = 'YYYY-MM-DD HH:mm'

export const formatDateTime = x => format(x, dateTimeFormat)
export const parseAndFormatDate = x => formatDateTime(Date.parse(x))
