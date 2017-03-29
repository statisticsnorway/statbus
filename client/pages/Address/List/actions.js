import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchAddressesStarted = createAction('fetch addresses started')
export const fetchAddressesFailed = createAction('fetch addresses failed')
export const fetchAddressesSuccessed = createAction('fetch addresses successed')

const fetchAddressList = () =>
  dispatchRequest({
    url: 'api/addresses',
    method: 'get',
    queryParams: { pageSize: 1000 }, // TODO: fix
    onStart: dispatch => dispatch(fetchAddressesStarted()),
    onSuccess: (dispatch, resp) => dispatch(fetchAddressesSuccessed(resp)),
    onFail: (dispatch, errors) => dispatch(fetchAddressesFailed(errors)),
  })

export default {
  fetchAddressList,
}
