import 'isomorphic-fetch'

import queryObjToString from './queryHelper'
import camelize from './stringToCamelCase'
import { actions as rqstActions } from './requestStatus'

const redirectToLogInPage = (onError) => {
  onError()
  window.location = `/account/login?urlReferrer=${encodeURIComponent(window.location.pathname)}`
}

const prettifyError = error =>
  Object.entries(error).reduce(
    (acc, [key, value]) => {
      const keyPrefix = key.length > 0
        ? `${camelize(key)}: `
        : ''
      return [
        ...acc,
        ...(Array.isArray(value)
          ? value
          : [value]).map(err => `${keyPrefix}${camelize(err)}`),
      ]
    },
    [],
  )

export const internalRequest = ({
  url = `/api${window.location.pathname}`,
  queryParams = {},
  method = 'get',
  body,
  onSuccess = f => f,
  onFail = f => f,
}) => {
  const fetchUrl = `${url}?${queryObjToString(queryParams)}`
  const fetchParams = {
    method,
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined,
    headers: method === 'put' || method === 'post'
      ? { 'Content-Type': 'application/json' }
      : undefined,
  }

  const handleFail = err => onFail(prettifyError(err))

  return method === 'get' || method === 'post'
    ? fetch(fetchUrl, fetchParams)
        .then(r => r.status < 300
          ? r.status === 204
            ? onSuccess()
            : r.json().then(onSuccess)
          : r.status === 401
            ? redirectToLogInPage(onFail)
            : r.status === 400
              ? r.json().then(onFail)
              : r.json().then(onFail))
        .catch(onFail)
    : fetch(fetchUrl, fetchParams)
        .then(r => r.status < 300
          ? onSuccess(r)
          : r.status === 401
            ? redirectToLogInPage(onFail)
            : r.json().then(onFail))
        .catch(onFail)
}

export default ({
  onStart = _ => _,
  onSuccess = _ => _,
  onFail = _ => _,
  ...rest
}) => (
  dispatch,
) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  onStart(dispatch)
  internalRequest({
    ...rest,
    onSuccess: (resp) => {
      onSuccess(dispatch, resp)
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      onFail(dispatch, errors)
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}
