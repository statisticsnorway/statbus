import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'
import { submitUserFailed } from '../Edit/actions'

const submitUser = data =>
  dispatchRequest({
    url: '/api/users',
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/users'))
    },
    onFail: (dispatch, error) => {
      if (error.login.includes('LoginError')) {
        dispatch(submitUserFailed(error))
      }
    },
  })

export default {
  submitUser,
  navigateBack,
}
