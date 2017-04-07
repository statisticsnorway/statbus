import { createAction } from 'redux-act'
import { goBack } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')
export const fetchStatUnit = (type, id) =>
  dispatchRequest({
    url: `/api/StatUnits/${type}/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchStatUnitSucceeded(resp))
    },
  })

export const navigateBack = () => dispatch => dispatch(goBack())

export const fetchHistorySucceeded = createAction('fetch History succeeded')
export const fetchHistoryStarted = createAction('fetch History started')

export const fetchHistory = (type, id) =>
  dispatchRequest({
    url: `/api/StatUnits/history/${type}/${id}`,
    onStart: (dispatch) => {
      dispatch(fetchHistoryStarted())
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchHistorySucceeded(resp))
    },
  })
