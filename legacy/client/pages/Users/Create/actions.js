import { push } from 'react-router-redux'
import { createAction } from 'redux-act'

import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'
import { submitUserFailed } from '../Edit/actions.js'

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
export const checkExistLogin = loginName =>
  dispatchRequest({
    url: `/api/users/isloginexist?login=${loginName}`,
    method: 'get',
    onSuccess: (dispatch, loginIsExist) => {
      dispatch(checkExistLoginSuccess(loginIsExist))
    },
  })

export default {
  submitUser,
  navigateBack,
  checkExistLogin,
  checkExistLoginSuccess,
}
