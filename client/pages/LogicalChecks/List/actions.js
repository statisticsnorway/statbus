import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const logicalChecksSucceded = createAction('logical checks succeded')
export const logicalChecksFalled = createAction('logical checks falled')
const logicalCheks = queryParams =>
  dispatchRequest({
    queryParams,
    url: '/api/statunits/analyzeregister',
    method: 'get',
    onSuccess: (dispatch, resp) => {
      dispatch(logicalChecksSucceded(resp))
    },
    onFail: (dispatch, errors) => dispatch(logicalChecksFalled(errors)),
  })

export default {
  logicalCheks,
}
