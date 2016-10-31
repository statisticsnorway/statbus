import { createAction } from 'redux-act'
import rqst from '../../../utils/fetch'

export const submitRoleStarted = createAction('submit role started')
export const submitRoleSucceeded = createAction('submit role succeeded')
export const submitRoleFailed = createAction('submit role failed')

export default {
  submitRole: data => (dispatch) => {
    dispatch(submitRoleStarted())
    rqst(
      '/api/roles',
      {},
      'post',
      data,
      () => { dispatch(submitRoleSucceeded()) },
      () => { dispatch(submitRoleFailed('bad request')) },
      () => { dispatch(submitRoleFailed('request failed')) }
    )
  },
}
