import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchRegionsStarted = createAction('fetch regions started')
export const fetchRegionsFailed = createAction('fetch regions failed')
export const fetchRegionsSuccessed = createAction('fetch regions successed')

const fetchRegions = queryParams =>
  dispatchRequest({
    queryParams,
    onStart: dispatch => dispatch(fetchRegionsStarted()),
    onSuccess: (dispatch, resp) => dispatch(fetchRegionsSuccessed(resp)),
    onFail: (dispatch, errors) => dispatch(fetchRegionsFailed(errors)),
  })

export const toggleDeleteRegionsStarted = createAction('toggle delete regions started')
export const toggleDeleteRegionsFailed = createAction('toggle delete regions failed')
export const toggleDeleteRegionsSuccessed = createAction('toggle delete regions successed')

const toggleDeleteRegion = (id, toggle) =>
  dispatchRequest({
    url: `/api/regions/${id}`,
    method: 'delete',
    queryParams: {
      delete: toggle,
    },
    onStart: dispatch => dispatch(toggleDeleteRegionsStarted()),
    onSuccess: dispatch => dispatch(toggleDeleteRegionsSuccessed({ id, isDeleted: toggle })),
    onFail: (dispatch, errors) => dispatch(toggleDeleteRegionsFailed(errors)),
  })

export const editRegionsStarted = createAction('edit regions started')
export const editRegionsFailed = createAction('edit regions failed')
export const editRegionsSuccessed = createAction('edit regions successed')

const editRegion = (id, data) =>
  dispatchRequest({
    url: `/api/regions/${id}`,
    method: 'put',
    body: data,
    onStart: dispatch => dispatch(editRegionsStarted()),
    onSuccess: dispatch => dispatch(editRegionsSuccessed({ id, ...data })),
    onFail: (dispatch, errors) => dispatch(editRegionsFailed(errors)),
  })

export const regionsEditorAction = createAction('regions editor action')
const editRegionRow = id => (dispatch) => {
  dispatch(regionsEditorAction(id))
}

export const regionAddEditorAction = createAction('regions adding editor action')
const addRegionEditor = visible => (dispatch) => {
  dispatch(regionAddEditorAction(visible))
}

export const addRegionsStarted = createAction('add regions started')
export const addRegionsFailed = createAction('add regions failed')
export const addRegionsSuccessed = createAction('add regions successed')

const addRegion = (data, queryParams) =>
  dispatchRequest({
    url: '/api/regions',
    method: 'post',
    body: data,
    onStart: dispatch => dispatch(addRegionsStarted()),
    onSuccess: (dispatch, resp) => {
      dispatch(addRegionsSuccessed(resp))
      dispatch(fetchRegions(queryParams))
    },
    onFail: (dispatch, errors) => dispatch(addRegionsFailed(errors)),
  })

export default {
  fetchRegions,
  toggleDeleteRegion,
  editRegion,
  editRegionRow,
  addRegionEditor,
  addRegion,
}
