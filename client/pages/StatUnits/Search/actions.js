import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import dispatchRequest from 'helpers/request'

export const fetchStatUnitsSucceeded = createAction('fetch StatUnits succeeded')

const fetchStatUnits = queryParams =>
  dispatchRequest({
    url: '/api/statunits',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchStatUnitsSucceeded({ ...resp, queryObj: queryParams }))
    },
  })

export const deleteStatUnitSucceeded = createAction('delete StatUnit succeeded')

const deleteStatUnit = (type, id) =>
  dispatchRequest({
    url: `/api/statunits/${type}/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(deleteStatUnitSucceeded(id))
      browserHistory.push('/statunits')
    },

  })

export default {
  fetchStatUnits,
  deleteStatUnit,
}
