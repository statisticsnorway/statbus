import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'

const submitUser = data =>
  dispatchRequest({
    url: '/api/users',
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/users'))
    },
  })

export default {
  submitUser,
  navigateBack,
}
