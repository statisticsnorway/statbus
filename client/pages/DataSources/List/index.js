import { connect } from 'react-redux'
import { merge, pipe } from 'ramda'

import { getText } from 'helpers/locale'
import { fetchDataSources, search, clear, deleteDataSource } from '../actions'
import List from './List'

export default connect(
  ({ dataSources: { searchForm, list, totalCount }, locale }, { location: { query } }) => ({
    formData: searchForm,
    query,
    totalCount,
    dataSources: list,
    localize: getText(locale),
  }),
  (dispatch, { location: { pathname, query } }) => ({
    fetchData: pipe(fetchDataSources, dispatch),
    onChange: pipe(search.updateFilter, dispatch),
    onSubmit: pipe(merge(query), search.setQuery(pathname), dispatch),
    onItemDelete: pipe(deleteDataSource, dispatch),
    clear: pipe(clear, dispatch),
  }),
)(List)
