import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchSoatesStarted = createAction('fetch soates started')
export const fetchSoatesFailed = createAction('fetch soates failed')
export const fetchSoatesSuccessed = createAction('fetch soates successed')

const fetchSoates = queryParams =>
  dispatchRequest({
    queryParams,
    onStart: dispatch => dispatch(fetchSoatesStarted()),
    onSuccess: (dispatch, resp) => dispatch(fetchSoatesSuccessed(resp)),
    onFail: (dispatch, errors) => dispatch(fetchSoatesFailed(errors)),
  })

export const toggleDeleteSoatesStarted = createAction('toggle delete soates started')
export const toggleDeleteSoatesFailed = createAction('toggle delete soates failed')
export const toggleDeleteSoatesSuccessed = createAction('toggle delete soates successed')

const toggleDeleteSoate = (id, toggle) =>
  dispatchRequest({
    url: `/api/soates/${id}`,
    method: 'delete',
    queryParams: {
      delete: toggle,
    },
    onStart: dispatch => dispatch(toggleDeleteSoatesStarted()),
    onSuccess: dispatch => dispatch(toggleDeleteSoatesSuccessed({ id, isDeleted: toggle })),
    onFail: (dispatch, errors) => dispatch(toggleDeleteSoatesFailed(errors)),
  })

export const editSoatesStarted = createAction('edit soates started')
export const editSoatesFailed = createAction('edit soates failed')
export const editSoatesSuccessed = createAction('edit soates successed')

const editSoate = (id, data) =>
  dispatchRequest({
    url: `/api/soates/${id}`,
    method: 'put',
    body: data,
    onStart: dispatch => dispatch(editSoatesStarted()),
    onSuccess: dispatch => dispatch(editSoatesSuccessed({ id, ...data })),
    onFail: (dispatch, errors) => dispatch(editSoatesFailed(errors)),
  })

export const soatesEditorAction = createAction('soates editor action')
const editSoateRow = id => (dispatch) => {
  dispatch(soatesEditorAction(id))
}

export const soateAddEditorAction = createAction('soates adding editor action')
const addSoateEditor = visible => (dispatch) => {
  dispatch(soateAddEditorAction(visible))
}

export const addSoatesStarted = createAction('add soates started')
export const addSoatesFailed = createAction('add soates failed')
export const addSoatesSuccessed = createAction('add soates successed')

const addSoate = (data, queryParams) =>
  dispatchRequest({
    url: '/api/soates',
    method: 'post',
    body: data,
    onStart: dispatch => dispatch(addSoatesStarted()),
    onSuccess: (dispatch, resp) => {
      dispatch(addSoatesSuccessed(resp))
      dispatch(fetchSoates(queryParams))
    },
    onFail: (dispatch, errors) => dispatch(addSoatesFailed(errors)),
  })

export default {
  fetchSoates,
  toggleDeleteSoate,
  editSoate,
  editSoateRow,
  addSoateEditor,
  addSoate,
}
