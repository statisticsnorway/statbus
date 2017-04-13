import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

const fetchDataSourcesSucceeded = createAction('fetch data sources succeeded')

const fetchDataSources = queryParams => dispatchRequest({
  url: '/api/datasources',
  queryParams,
  onSuccess: (dispatch, response) => dispatch(fetchDataSourcesSucceeded(response)),
})

export const list = {
  fetchDataSources,
}

export default {
  fetchDataSourcesSucceeded,
}
