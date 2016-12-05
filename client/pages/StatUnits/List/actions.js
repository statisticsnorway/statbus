import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchStatUnitsSucceeded = createAction('fetch StatUnits succeeded')

const fetchStatUnits = () => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    onSuccess: (resp) => {
      dispatch(fetchStatUnitsSucceeded(resp))
      dispatch(rqstActions.succeeded())
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export const deleteStatUnitSucceeded = createAction('delete StatUnit succeeded')

const deleteStatUnit = id => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: `/api/StatUnits/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteStatUnitSucceeded(id))
      dispatch(rqstActions.succeeded())
      browserHistory.push('/StatUnits')
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export default {
  fetchStatUnits,
  deleteStatUnit,
}
