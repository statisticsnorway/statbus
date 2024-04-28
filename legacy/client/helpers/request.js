import 'isomorphic-fetch'
import { push } from 'react-router-redux'
import * as R from 'ramda'

import {
  request as rqstActions,
  notification as notificationActions,
  authentication as authenticationActions,
} from './actionCreators.js'
import queryObjectToString from './queryObjectToString.js'

export const internalRequest = ({
  url = `/api${window.location.pathname}`,
  queryParams = {},
  method = 'get',
  body,
  onSuccess = R.identity,
  onFail = R.identity,
  onForbidden = R.identity,
  onUnauthorized = undefined,
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
          return onUnauthorized === undefined ? onFail() : onUnauthorized()
        case 403:
          return onForbidden()
        default:
          return resp.status < 300
            ? method === 'get' || method === 'post'
              ? resp.json().then(onSuccess)
              : onSuccess(resp)
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
  onStart = R.identity,
  onSuccess = R.identity,
  onFail = R.identity,
}) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.payload.id
  dispatch(startedAction)
  onStart(dispatch)
  return new Promise((resolve, reject) => {
    const errorHandler = (error) => {
      onFail(dispatch, error)
      dispatch(rqstActions.failed(error))
      dispatch(rqstActions.dismiss(startedId))
      reject(error)
    }

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
      onFail: errorHandler,
      onForbidden: () => {
        showForbiddenNotificationAndRedirect(dispatch)
        reject()
      },
      onUnauthorized: () => {
        dispatch(authenticationActions.showAuthentication())
        errorHandler()
      },
    })
  })
}

export default ({
  url,
  queryParams,
  method,
  body,
  onStart = R.identity,
  onSuccess = R.identity,
  onFail = R.identity,
}) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.payload.id

  const errorHandler = (error) => {
    onFail(dispatch, error)
    dispatch(rqstActions.failed(error))
    dispatch(rqstActions.dismiss(startedId))
  }

  dispatch(startedAction)
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
    onFail: errorHandler,
    onForbidden: () => {
      showForbiddenNotificationAndRedirect(dispatch)
    },
    onUnauthorized: () => {
      errorHandler()
      dispatch(authenticationActions.showAuthentication())
    },
  })
}
