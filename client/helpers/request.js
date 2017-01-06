import 'isomorphic-fetch'
import { queryObjToString } from 'helpers/queryHelper'

import { pascalCaseToCamelCase } from './string'

const redirectToLogInPage = (onError) => {
  onError()
  window.location = `/account/login?urlReferrer=${encodeURIComponent(window.location.pathname)}`
}

const prettifyError = error => Object.keys(error).reduce(
  (acc, key) => {
    const value = error[key]
    const keyPrefix = key.length > 0 ? `${pascalCaseToCamelCase(key)}: ` : ''
    return [
      ...acc,
      ...(Array.isArray(value)
        ? value
        : [value]).map(err => `${keyPrefix}${pascalCaseToCamelCase(err)}`),
    ]
  },
  [],
)

export default ({
  url = `/api${window.location.pathname}`,
  queryParams = {},
  method = 'get',
  body,
  onSuccess = f => f,
  onFail = f => f,
  onError = f => f,
}) => {
  const fetchUrl = url + queryObjToString(queryParams)
  const fetchParams = {
    method,
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined,
    headers: method === 'put' || method === 'post'
      ? { 'Content-Type': 'application/json' }
      : undefined,
  }
  const handleFail = err => onFail(prettifyError(err))
  if (method === 'get' || method === 'post') {
    fetch(fetchUrl, fetchParams)
      .then(r => r.status < 300
        ? r.status === 204
          ? onSuccess()
          : r.json().then(onSuccess)
        : r.status === 401
          ? redirectToLogInPage(onError)
          : r.json().then(handleFail))
      .catch(onError)
  } else {
    fetch(fetchUrl, fetchParams)
      .then(r => r.status < 300
        ? onSuccess(r)
        : r.status === 401
          ? redirectToLogInPage(onError)
          : r.json().then(handleFail))
      .catch(onError)
  }
}
