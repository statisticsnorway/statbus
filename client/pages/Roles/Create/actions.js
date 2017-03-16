import { browserHistory } from 'react-router'

import dispatchRequest from 'helpers/request'

export default {
  submitRole: data => dispatchRequest({
    url: '/api/roles',
    method: 'post',
    body: data,
    onSuccess: () => {
      browserHistory.push('/roles')
    },
  }),
}
