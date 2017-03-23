import 'isomorphic-fetch'
import { browserHistory } from 'react-router'
import queryObjToString from './queryHelper'
import { actions as rqstActions } from './requestStatus'
import { actions as notificationActions } from './notification'

const redirectToLogInPage = (onError) => {
  onError()
  window.location = `/account/login?urlReferrer=${encodeURIComponent(window.location.pathname)}`
}
const showForbiddenNotificationAndRedirect = (dispatch) => {
  dispatch(notificationActions.showNotification('Error403'))
  browserHistory.push('/')
}

export const internalRequest = ({
  url = `/api${window.location.pathname}`,
  queryParams = {},
  method = 'get',
  body,
  onSuccess = f => f,
  onFail = f => f,
  onForbidden = f => f,
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

  return method === 'get' || method === 'post'
    ? fetch(fetchUrl, fetchParams)
      .then((r) => {
        switch (r.status) {
          case 204:
            return onSuccess()
          case 401:
            return redirectToLogInPage(onFail)
          case 403:
            return onForbidden()
          default:
            return r.status < 300 ? r.json().then(onSuccess) : r.json().then(onFail)
        }
      })
      .catch(onFail)
    : fetch(fetchUrl, fetchParams)
      .then((r) => {
        switch (r.status) {
          case 401:
            return redirectToLogInPage(onFail)
          case 403:
            return onForbidden()
          default:
            return r.status < 300 ? onSuccess(r) : r.json().then(onFail)
        }
      })
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
    onForbidden: () => showForbiddenNotificationAndRedirect(dispatch),
  })
}
