import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

export default {
  submitAddress: data =>
    dispatchRequest({
      url: '/api/addresses',
      method: 'post',
      body: data,
      onSuccess: (dispatch) => {
        dispatch(push('/addresses'))
      },
    }),
}
