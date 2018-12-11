import { push } from 'react-router-redux'
import { createAction } from 'redux-act'

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

export const checkExistLoginSuccess = createAction('check existing login success')
const checkExistLogin = loginName =>
  dispatchRequest({
    url: '',
    method: 'post',
    body: loginName,
    onSuccess: (dispatch, data) => {
      dispatch(checkExistLoginSuccess(data))
    },
  })

export default {
  submitUser,
  navigateBack,
  checkExistLogin,
}
