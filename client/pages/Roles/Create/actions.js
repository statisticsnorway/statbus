import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const submitRoleStarted = createAction('submit role started')
export const submitRoleSucceeded = createAction('submit role succeeded')
export const submitRoleFailed = createAction('submit role failed')

export default {
  submitRole: data => (dispatch) => {
    dispatch(submitRoleStarted())
    rqst({
      url: '/api/roles',
      method: 'post',
      body: data,
      onSuccess: () => { dispatch(submitRoleSucceeded()) },
      onFail: () => { dispatch(submitRoleFailed('bad request')) },
      onError: () => { dispatch(submitRoleFailed('request failed')) },
    })
  },
}
