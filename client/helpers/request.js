import 'isomorphic-fetch'
import { push } from 'react-router-redux'

import { request as rqstActions, notification as notificationActions } from './actionCreators'
import queryObjectToString from './queryObjectToString'

const redirectToLogInPage = (onError) => {
  onError()
  window.location = `/account/login?urlReferrer=${encodeURIComponent(window.location.pathname)}`
}

const stubF = _ => _

export const internalRequest = ({
  url = `/api${window.location.pathname}`,
  queryParams = {},
  method = 'get',
  body,
  onSuccess = stubF,
  onFail = stubF,
  onForbidden = stubF,
}) =>
  fetch(`${url}${queryObjectToString(queryParams)}`, {
    method,
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
  })
    .then((resp) => {
      switch (resp.status) {
        case 204:
          return onSuccess()
        case 401:
          return redirectToLogInPage(onFail)
        case 403:
          return onForbidden()
        default:
          return resp.status < 300
            ? method === 'get' || method === 'post' ? resp.json().then(onSuccess) : onSuccess(resp)
            : resp.json().then(onFail)
      }
    })
    .catch((error) => {
      console.error(error) // eslint-disable-line no-console
      onFail(error)
    })

const showForbiddenNotificationAndRedirect = (dispatch) => {
  dispatch(notificationActions.showNotification({ body: 'Error403' }))
  dispatch(push('/'))
}

export const reduxRequest = ({
  url,
  queryParams,
  method,
  body,
  onStart = stubF,
  onSuccess = stubF,
  onFail = stubF,
}) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.id
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
      onFail: (error) => {
        onFail(dispatch, error)
        dispatch(rqstActions.failed(error))
        dispatch(rqstActions.dismiss(startedId))
        reject(error)
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
  onStart = stubF,
  onSuccess = stubF,
  onFail = stubF,
}) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.id
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
    onFail: (error) => {
      onFail(dispatch, error)
      dispatch(rqstActions.failed(error))
      dispatch(rqstActions.dismiss(startedId))
    },
    onForbidden: () => {
      showForbiddenNotificationAndRedirect(dispatch)
    },
  })
}
