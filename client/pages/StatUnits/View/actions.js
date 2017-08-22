import { createAction } from 'redux-act'

import dispatchRequest, { reduxRequest } from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'

export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')
export const fetchHistorySucceeded = createAction('fetch History succeeded')
export const fetchHistoryStarted = createAction('fetch History started')
export const fetchHistoryDetailsSucceeded = createAction('fetch History Details succeeded')
export const fetchHistoryDetailsStarted = createAction('fetch History Details started')
export const fetchCountryNameSucceeded = createAction('fetch Countries succeeded')

const fetchStatUnit = (type, id) =>
  dispatchRequest({
    url: `/api/StatUnits/${type}/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchStatUnitSucceeded(resp))
    },
  })

const fetchCountryName = (type, id) =>
  dispatchRequest({
    url: `/api/statunits/GetCountryName/${type}/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchCountryNameSucceeded(resp))
    },
  })

const fetchHistory = (type, id) =>
  dispatchRequest({
    url: `/api/StatUnits/history/${type}/${id}`,
    onStart: (dispatch) => {
      dispatch(fetchHistoryStarted())
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchHistorySucceeded(resp))
    },
  })

const fetchHistoryDetails = (type, id) =>
  dispatchRequest({
    url: `/api/StatUnits/historyDetails/${type}/${id}`,
    onStart: (dispatch) => {
      dispatch(fetchHistoryDetailsStarted())
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchHistoryDetailsSucceeded(resp))
    },
  })

const getUnitLinks = data =>
  reduxRequest({
    url: '/api/links/search',
    queryParams: { source: data },
  })

const getOrgLinks = queryParams =>
  reduxRequest({
    url: '/api/statunits/getorglinkstree',
    queryParams,
  })

export default {
  fetchStatUnit,
  navigateBack,
  fetchHistory,
  fetchHistoryDetails,
  getUnitLinks,
  getOrgLinks,
  fetchCountryName,
}
