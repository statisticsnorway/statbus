import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchEnterpriseUnitsLookupSucceeded = createAction('fetch EnterpriseUnitsLookup succeeded')

export const fetchEnterpriseUnitsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/3',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchEnterpriseUnitsLookupSucceeded(resp))
    },
  })

export const fetchEnterpriseGroupsLookupSucceeded = createAction('fetch EnterpriseGroupsLookup succeeded')

export const fetchEnterpriseGroupsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/4',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchEnterpriseGroupsLookupSucceeded(resp))
    },
  })

export const fetchLegalUnitsLookupSucceeded = createAction('fetch LegalUnitsLookup succeeded')

export const fetchLegalUnitsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/2',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLegalUnitsLookupSucceeded(resp))
    },
  })

export const fetchLocallUnitsLookupSucceeded = createAction('fetch LocallUnitsLookup succeeded')

export const fetchLocallUnitsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/1',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLocallUnitsLookupSucceeded(resp))
    },
  })
