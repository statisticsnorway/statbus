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
  `${url}?${queryObjToString(queryParams)}`,
  {
    method,
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined,
    headers: method === 'put' || method === 'post'
      ? { 'Content-Type': 'application/json' }
      : undefined,
  },
).then((r) => {
  switch (r.status) {
    case 204:
      return onSuccess()
    case 401:
      return redirectToLogInPage(onFail)
    case 403:
      return onForbidden()
    default:
      return r.status < 300
        ? method === 'get' || method === 'post'
          ? r.json().then(onSuccess)
          : onSuccess(r)
        : r.json().then(onFail)
  }
})
.catch(onFail)

const showForbiddenNotificationAndRedirect = (dispatch) => {
  dispatch(notificationActions.showNotification('Error403'))
  dispatch(push('/'))
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
  internalRequest({
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
    onForbidden: () => showForbiddenNotificationAndRedirect(dispatch),
  })
}
