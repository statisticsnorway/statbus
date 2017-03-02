import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchStatUnitsSucceeded = createAction('fetch StatUnits succeeded')

const fetchStatUnits = queryParams => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: '/api/statunits',
    queryParams,
    onSuccess: (resp) => {
      dispatch(fetchStatUnitsSucceeded({ ...resp, queryObj: queryParams }))
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

export const deleteStatUnitSucceeded = createAction('delete StatUnit succeeded')

const deleteStatUnit = (type, id) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/statunits/${type}/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteStatUnitSucceeded(id))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
      browserHistory.push('/statunits')
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
  fetchStatUnits,
  deleteStatUnit,
}
