import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const fetchUserStarted = createAction('fetch user started')
export const fetchUserSucceeded = createAction('fetch user succeeded')
export const fetchUserFailed = createAction('fetch user failed')
const fetchUser = id => (dispatch) => {
  dispatch(fetchUserStarted())
  rqst({
    url: `/api/users/${id}`,
    onSuccess: (resp) => { dispatch(fetchUserSucceeded(resp)) },
    onFail: () => { dispatch(fetchUserFailed('bad request')) },
    onError: () => { dispatch(fetchUserFailed('request failed')) },
  })
}

export const submitUserStarted = createAction('submit user started')
export const submitUserSucceeded = createAction('submit user succeeded')
export const submitUserFailed = createAction('submit user failed')
const submitUser = ({ id, ...data }) => (dispatch) => {
  dispatch(submitUserStarted())
  rqst({
    url: `/api/users/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => { dispatch(submitUserSucceeded()) },
    onFail: () => { dispatch(submitUserFailed('bad request')) },
    onError: () => { dispatch(submitUserFailed('request failed')) },
  })
}

export const editForm = createAction('edit user form')

export default {
  editForm,
  submitUser,
  fetchUser,
}
