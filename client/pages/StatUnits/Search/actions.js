import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'
import { updateFilter, setQuery } from '../actions'

export const fetchDataSucceeded = createAction('fetch StatUnits succeeded')
const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/statunits',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchDataSucceeded({ ...resp, queryObj: queryParams }))
    },
  })

const deleteStatUnit = (type, id, queryParams) =>
  dispatchRequest({
    url: `/api/statunits/${type}/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(fetchData(queryParams))
    },
  })

export default {
  updateFilter,
  setQuery,
  fetchData,
  deleteStatUnit,
}
