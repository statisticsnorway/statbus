import { createAction } from 'redux-act'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')
export const fetchStatUnit = (type, id) => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: `/api/StatUnits/${type}/${id}`,
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchStatUnitSucceeded(resp))
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
