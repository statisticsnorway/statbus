import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

export default {
  submitUser: data =>
    dispatchRequest({
      url: '/api/users',
      method: 'post',
      body: data,
      onSuccess: (dispatch) => {
        dispatch(push('/users'))
      },
    }),
}
