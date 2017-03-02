import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

const fetchStatUnitSucceeded = data => ({ type: 'FETCH_STATUNIT_SUCCEEDED', data })

const fetchData = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: '/api/statunits/deleted',
    onSuccess: (data) => {
      dispatch(fetchStatUnitSucceeded(data))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

const restoreSucceeded = data => ({ type: 'RESTORE_STATUNIT_SUCCEEDED', data })

const restore = (type, regId) => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    method: 'delete',
    url: '/api/statunits/deleted',
    queryParams: { type, regId },
    onSuccess: () => {
      dispatch(restoreSucceeded(regId))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export default {
  fetchData,
  restore,
}
