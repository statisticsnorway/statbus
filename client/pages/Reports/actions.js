import dispatchRequest from '/client/helpers/request'
import { navigateBack } from '/client/helpers/actionCreators'
import { createAction } from 'redux-act'

export const fetchReportsTreeSucceeded = createAction('Fetch reports Tree')

const fetchReportsTree = () =>
  dispatchRequest({
    url: '/api/reports/getreportstree',
    method: 'get',
    onSuccess: (dispatch, resp) => {
      dispatch(fetchReportsTreeSucceeded(resp))
    },
  })

export default {
  fetchReportsTree,
  navigateBack,
}
