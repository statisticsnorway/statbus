import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'

const fetchAccount = handleOk =>
  dispatchRequest({
    url: '/api/account/details',
    onSuccess: (_, resp) => {
      handleOk(resp)
    },
  })

const submitAccount = (data, formCallbacks) =>
  dispatchRequest({
    url: '/api/account/details',
    method: 'post',
    body: data,
    onStart: formCallbacks.started,
    onSuccess: (dispatch) => {
      dispatch(push('/'))
    },
    onFail: (_, errors) => {
      formCallbacks.failed(errors)
    },
  })

export default {
  fetchAccount,
  submitAccount,
  navigateBack,
}
