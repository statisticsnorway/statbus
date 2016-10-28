import { createAction } from 'redux-act'
import { post } from '../../../utils/fetch'

export const submitRoleStarted = createAction('submit role started')
export const submitRoleSucceeded = createAction('submit role succeeded')
export const submitRoleFailed = createAction('submit role failed')

export default {
  submitRole: data => (dispatch) => {
    dispatch(submitRoleStarted())
    post(
      data,
      '/api/roles/createrole',
      () => { dispatch(submitRoleSucceeded()) },
      () => { dispatch(submitRoleFailed('bad request')) },
      () => { dispatch(submitRoleFailed('request failed')) }
    )
  },
}
