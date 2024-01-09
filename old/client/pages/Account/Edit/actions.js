import { push } from 'react-router-redux'

import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'

const fetchAccount = handleOk =>
  dispatchRequest({
    url: '/api/account/details',
    onSuccess: (_, resp) => {
      handleOk(resp)
    },
  })

const submitAccount = (body, formikBag) =>
  dispatchRequest({
    url: '/api/account/details',
    method: 'post',
    body,
    onStart: () => {
      formikBag.started()
    },
    onSuccess: (dispatch) => {
      dispatch(push('/'))
    },
    onFail: (_, errors) => {
      formikBag.failed(errors)
    },
  })

export default {
  fetchAccount,
  submitAccount,
  navigateBack,
}
