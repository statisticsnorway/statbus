import moment from 'moment'

export const momentLocale = x => moment.locale(x)
export const toUtc = x =>
  moment(x)
    .utc()
    .format()
export const format = x => moment(x).format()

export const dateFormat = 'YYYY-MM-DD'
export const dateTimeFormat = 'YYYY-MM-DD HH:mm'

export const formatDate = x => moment(x).format(dateFormat)
export const formatDateTime = x => moment(x).format(dateTimeFormat)
export const getDate = (utcString = null) => (utcString ? moment(utcString) : moment())
