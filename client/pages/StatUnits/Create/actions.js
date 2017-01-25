import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'
import typeNames from 'helpers/statUnitTypes'

export const editForm = createAction('edit form')
export const clearForm = createAction('clear form')

export const submitStatUnit = ({ type, ...data }) =>
  (dispatch) => {
    const startedAction = rqstActions.started()
    const { data: { id: startedId } } = startedAction
    dispatch(startedAction)
    const typeName = typeNames.get(Number(type))
    return rqst({
      url: `/api/statunits/${typeName}`,
      method: 'post',
      body: data,
      onSuccess: () => {
        dispatch(clearForm())
        dispatch(rqstActions.succeeded())
        browserHistory.push('/statunits')
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

