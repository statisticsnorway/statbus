import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const submitUserStarted = createAction('submit user started')
export const submitUserSucceeded = createAction('submit user succeeded')
export const submitUserFailed = createAction('submit user failed')

export default {
  submitUser: data => (dispatch) => {
    dispatch(submitUserStarted())
    rqst({
      url: '/api/users',
      method: 'post',
      body: data,
      onSuccess: () => { dispatch(submitUserSucceeded()) },
      onFail: () => { dispatch(submitUserFailed('bad request')) },
      onError: () => { dispatch(submitUserFailed('request failed')) },
    })
  },
}
