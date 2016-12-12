import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchStatUnitsSucceeded = createAction('fetch StatUnits succeeded')

const fetchStatUnits = queryParams => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: 'api/search',
    queryParams,
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
    url: `/api/statunits/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteStatUnitSucceeded(id))
      dispatch(rqstActions.succeeded())
      browserHistory.push('/statunits')
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export default {
  fetchStatUnits,
  deleteStatUnit,
}
