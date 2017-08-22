import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'

const fetchAccount = handleOk => dispatchRequest({
  url: '/api/account/details',
  onSuccess: (_, resp) => {
    handleOk(resp)
  },
})

const submitAccount = data => dispatchRequest({
  url: '/api/account/details',
  method: 'post',
  body: data,
  onSuccess: (dispatch) => {
    dispatch(push('/'))
  },
})

export default {
  submitAccount,
  fetchAccount,
  navigateBack,
}
