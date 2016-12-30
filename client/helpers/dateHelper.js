import moment from 'moment'

export const toUtc = x => moment(x).utc().format()
export const format = x => moment(x).format()

export const dateTimeFormat = 'YYYY-MM-DD HH:mm'

export const formatDateTime = x => moment(x).format(dateTimeFormat)
