import { browserHistory } from 'react-router'

import dispatchRequest from 'helpers/request'

export default {
  submitUser: data =>
    dispatchRequest({
      url: '/api/users',
      method: 'post',
      body: data,
      onSuccess: () => {
        browserHistory.push('/users')
      },
    }),
}
