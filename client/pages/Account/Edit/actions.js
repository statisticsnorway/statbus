import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const fetchAccountStarted = createAction('fetch account started')
export const fetchAccountSucceeded = createAction('fetch account succeeded')
export const fetchAccountFailed = createAction('fetch account failed')
const fetchAccount = () => (dispatch) => {
  dispatch(fetchAccountStarted())
  rqst({
    url: '/api/account/details',
    onSuccess: (resp) => { dispatch(fetchAccountSucceeded(resp)) },
    onFail: () => { dispatch(fetchAccountFailed('bad request')) },
    onError: () => { dispatch(fetchAccountFailed('request failed')) },
  })
}

export const submitAccountStarted = createAction('submit account started')
export const submitAccountSucceeded = createAction('submit account succeeded')
export const submitAccountFailed = createAction('submit account failed')
const submitAccount = data => (dispatch) => {
  dispatch(submitAccountStarted())
  rqst({
    url: '/api/account/details',
    method: 'post',
    body: data,
    onSuccess: () => { dispatch(submitAccountSucceeded()) },
    onFail: () => { dispatch(submitAccountFailed('bad request')) },
    onError: () => { dispatch(submitAccountFailed('request failed')) },
  })
}

export const editForm = createAction('edit account form')

export default {
  editForm,
  submitAccount,
  fetchAccount,
}
