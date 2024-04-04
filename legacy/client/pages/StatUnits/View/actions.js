import { createAction } from 'redux-act'

import dispatchRequest, { reduxRequest } from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'

export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')
export const fetchHistorySucceeded = createAction('fetch History succeeded')
export const fetchHistoryStarted = createAction('fetch History started')
export const fetchStatUnitFailed = createAction('fetch StatUnit failed')
export const fetchHistoryDetailsSucceeded = createAction('fetch History Details succeeded')
export const fetchHistoryDetailsStarted = createAction('fetch History Details started')
export const fetchSectorSucceeded = createAction('fetch Sector succeeded')
export const fetchLegalFormSucceeded = createAction('fetch LegalForm succeeded')
export const fetchUnitStatusSucceeded = createAction('fetch UnitStatus succeeded')
export const clear = createAction('clear')

const fetchSector = sectorCodeId =>
  dispatchRequest({
    url: `/api/statunits/GetSector/${sectorCodeId}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchSectorSucceeded(resp))
    },
  })

const fetchLegalForm = legalFormId =>
  dispatchRequest({
    url: `/api/statunits/GetLegalForm//${legalFormId}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLegalFormSucceeded(resp))
    },
  })

const fetchUnitStatus = unitStatusId =>
  dispatchRequest({
    url: `/api/lookup/9/GetById/?ids=${unitStatusId}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchUnitStatusSucceeded(resp[0].name))
    },
  })

const fetchStatUnit = (type, id) =>
  dispatchRequest({
    url: `/api/StatUnits/${type}/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchStatUnitSucceeded(resp))
      if (resp.instSectorCodeId) {
        dispatch(fetchSector(resp.instSectorCodeId))
      }
      if (resp.legalFormId) {
        dispatch(fetchLegalForm(resp.legalFormId))
      }
      if (resp.unitStatusId) {
        dispatch(fetchUnitStatus(resp.unitStatusId))
      }
    },
    onFail: (dispatch, resp) => {
      dispatch(fetchStatUnitFailed(resp))
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

const fetchHistoryDetails = (type, id, isHistory) =>
  dispatchRequest({
    url: `/api/StatUnits/historyDetails/${type}/${id}/${isHistory}`,
    onStart: (dispatch) => {
      dispatch(fetchHistoryDetailsStarted())
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchHistoryDetailsSucceeded(resp))
    },
  })

const getUnitLinks = queryParams =>
  reduxRequest({
    url: '/api/links/search',
    queryParams,
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
  fetchSector,
  fetchLegalForm,
  fetchUnitStatus,
  clear,
}
