import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export default {
  submitRole: data => (dispatch) => {
    const startedAction = rqstActions.started()
    const startedId = startedAction.data.id
    dispatch(startedAction)
    rqst({
      url: '/api/roles',
      method: 'post',
      body: data,
      onSuccess: () => {
        dispatch(rqstActions.succeeded())
        dispatch(rqstActions.dismiss(startedId))
        browserHistory.push('/roles')
      },
      onFail: (errors) => {
        dispatch(rqstActions.failed({ errors }))
        dispatch(rqstActions.dismiss(startedId))
      },
      onError: (errors) => {
        dispatch(rqstActions.failed({ errors }))
        dispatch(rqstActions.dismiss(startedId))
      },
    })
  },
}
