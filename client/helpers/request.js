import 'isomorphic-fetch'
import { push } from 'react-router-redux'

import queryObjToString from './queryHelper'
import { actions as rqstActions } from './requestStatus'
import { actions as notificationActions } from './notification'

const redirectToLogInPage = (onError) => {
  onError()
  window.location = `/account/login?urlReferrer=${encodeURIComponent(window.location.pathname)}`
}

export const internalRequest = ({
  url = `/api${window.location.pathname}`,
  queryParams = {},
  method = 'get',
  body,
  onSuccess = _ => _,
  onFail = _ => _,
  onForbidden = _ => _,
}) => fetch(
  `${url}${queryObjToString(queryParams)}`,
  {
    method,
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined,
    headers: body
      ? { 'Content-Type': 'application/json' }
      : undefined,
  },
).then(
  (resp) => {
    switch (resp.status) {
      case 204:
        return onSuccess()
      case 401:
        return redirectToLogInPage(onFail)
      case 403:
        return onForbidden()
      default:
        return resp.status < 300
          ? method === 'get' || method === 'post'
            ? resp.json().then(onSuccess)
            : onSuccess(resp)
          : resp.json().then(onFail)
    }
  },
).catch(
  (errors) => {
    console.log(errors) // eslint-disable-line no-console
    onFail(errors)
  },
)

const showForbiddenNotificationAndRedirect = (dispatch) => {
  dispatch(notificationActions.showNotification({ body: 'Error403' }))
  dispatch(push('/'))
}

export const reduxRequest = ({
  url,
  queryParams,
  method,
  body,
  onStart = _ => _,
  onSuccess = _ => _,
  onFail = _ => _,
}) => (
  dispatch,
) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  onStart(dispatch)
  return new Promise((resolve, reject) => {
    internalRequest({
      url,
      queryParams,
      method,
      body,
      onSuccess: (resp) => {
        onSuccess(dispatch, resp)
        dispatch(rqstActions.succeeded())
        dispatch(rqstActions.dismiss(startedId))
        resolve(resp)
      },
      onFail: (errors) => {
        onFail(dispatch, errors)
        dispatch(rqstActions.failed(errors))
        dispatch(rqstActions.dismiss(startedId))
        reject(errors)
      },
      onForbidden: () => {
        showForbiddenNotificationAndRedirect(dispatch)
        reject()
      },
    })
  })
}

export default ({
  url,
  queryParams,
  method,
  body,
  onStart = _ => _,
  onSuccess = _ => _,
  onFail = _ => _,
}) => (
  dispatch,
) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  onStart(dispatch)
  return internalRequest({
    url,
    queryParams,
    method,
    body,
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
    onForbidden: () => {
      showForbiddenNotificationAndRedirect(dispatch)
    },
  })
}
