import { connect } from 'react-redux'
import { merge, pipe } from 'ramda'

import { getText } from '/helpers/locale'
import { fetchDataSources, search, clear, deleteDataSource, fetchError } from '../actions.js'
import List from './List.jsx'

export default connect(
  ({ dataSources: { searchForm, list, totalCount, errors }, locale }, { location: { query } }) => ({
    formData: searchForm,
    query,
    totalCount,
    dataSources: list,
    localize: getText(locale),
    errors,
  }),
  (dispatch, { location: { pathname, query } }) => ({
    fetchData: pipe(fetchDataSources, dispatch),
    onChange: pipe(search.updateFilter, dispatch),
    onSubmit: pipe(merge(query), search.setQuery(pathname), dispatch),
    onItemDelete: pipe(deleteDataSource, dispatch),
    fetchError: errors => dispatch(fetchError(errors)),
    clear: pipe(clear, dispatch),
  }),
)(List)
