import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'
import typeNames from 'helpers/statUnitTypes'

const submitStatUnit = ({ type, ...data }) => (dispatch) => {
  dispatch(rqstActions.started())
  const typeName = typeNames.get(type)
  rqst({
    url: `/api/statunits/${typeName}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      dispatch(rqstActions.succeeded())
      browserHistory.push('/statunits')
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
    },
  })
}

export const editForm = createAction('edit stat unit form')
export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')

const fetchStatUnit = id => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: `/api/StatUnits/${id}`,
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchStatUnitSucceeded(resp))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export default {
  editForm,
  submitStatUnit,
  fetchStatUnitSucceeded,
  fetchStatUnit,
}
