import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import R from 'ramda'

import dispatchRequest from 'helpers/request'

export const updateFilter = createAction('update search form')

export const setQuery = pathname => query => (dispatch) => {
  R.pipe(updateFilter, dispatch)(query)
  const type = query.type === 'any' ? undefined : query.type
  R.pipe(push, dispatch)({ pathname, query: { ...query, type } })
}

export const fetchEnterpriseUnitsLookupSucceeded = createAction('fetch EnterpriseUnitsLookup succeeded')
export const fetchEnterpriseGroupsLookupSucceeded = createAction('fetch EnterpriseGroupsLookup succeeded')
export const fetchLegalUnitsLookupSucceeded = createAction('fetch LegalUnitsLookup succeeded')
export const fetchLocallUnitsLookupSucceeded = createAction('fetch LocallUnitsLookup succeeded')

const fetchEnterpriseUnitsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/3',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchEnterpriseUnitsLookupSucceeded(resp))
    },
  })

const fetchEnterpriseGroupsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/4',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchEnterpriseGroupsLookupSucceeded(resp))
    },
  })

const fetchLegalUnitsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/2',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLegalUnitsLookupSucceeded(resp))
    },
  })

const fetchLocallUnitsLookup = () =>
  dispatchRequest({
    url: '/api/StatUnits/GetStatUnits/1',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchLocallUnitsLookupSucceeded(resp))
    },
  })

export default {
  fetchEnterpriseUnitsLookup,
  fetchEnterpriseGroupsLookup,
  fetchLegalUnitsLookup,
  fetchLocallUnitsLookup,
}
