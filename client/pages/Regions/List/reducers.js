import { createReducer } from 'redux-act'

import * as actions from './actions'

const initialState = {
  regions: [],
  totalCount: 0,
  fetching: false,
  error: undefined,
  editRow: undefined,
  addingRegion: false,
}

const regions = createReducer(
  {
    [actions.fetchRegionsSuccessed]: (state, data) => ({
      ...state,
      regions: data.result,
      totalCount: data.totalCount,
      fetching: false,
      error: undefined,
    }),
    [actions.fetchRegionsFailed]: (state, data) => ({
      ...state,
      regions: [],
      totalCount: 0,
      fetching: false,
      error: data,
    }),
    [actions.fetchRegionsStarted]: state => ({
      ...state,
      fetching: true,
      error: undefined,
    }),
    [actions.toggleDeleteRegionsStarted]: state => ({
      ...state,
      fetching: true,
      error: undefined,
    }),
    [actions.toggleDeleteRegionsSuccessed]: (state, { id, isDeleted }) => ({
      ...state,
      regions: state.regions.map(x => (x.id !== id ? x : { ...x, isDeleted })),
      error: undefined,
      fetching: false,
    }),
    [actions.toggleDeleteRegionsFailed]: (state, data) => ({
      ...state,
      error: data,
      fetching: false,
    }),
    [actions.editRegionsStarted]: state => ({
      ...state,
      fetching: true,
    }),
    [actions.editRegionsSuccessed]: (state, data) => ({
      ...state,
      error: undefined,
      fetching: false,
      regions: state.regions.map(v => (v.id === data.id ? data : v)),
      editRow: undefined,
    }),
    [actions.editRegionsFailed]: (state, data) => ({
      ...state,
      fetching: false,
      error: data,
    }),
    [actions.regionsEditorAction]: (state, data) => ({
      ...state,
      editRow: data,
    }),
    [actions.regionAddEditorAction]: (state, data) => ({
      ...state,
      addingRegion: data,
    }),
    [actions.addRegionsStarted]: state => ({
      ...state,
      fetching: true,
    }),
    [actions.addRegionsSuccessed]: (state, data) => ({
      ...state,
      error: undefined,
      fetching: false,
      regions: [data, ...state.regions],
      addingRegion: false,
    }),
    [actions.addRegionsFailed]: (state, data) => ({
      ...state,
      fetching: false,
      error: data,
    }),
  },
  initialState,
)

export default {
  regions,
}
