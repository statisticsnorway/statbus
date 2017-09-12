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

const submitAccount = (data, formikBag) =>
  dispatchRequest({
    url: '/api/account/details',
    method: 'post',
    body: data,
    onStart: () => {
      formikBag.setSubmitting(true)
    },
    onSuccess: (dispatch) => {
      dispatch(push('/'))
    },
    onFail: (_, errors) => {
      formikBag.setSubmitting(false)
      formikBag.setStatus({ errors })
    },
  })

export default {
  submitAccount,
  fetchAccount,
  onCancel: navigateBack,
}
