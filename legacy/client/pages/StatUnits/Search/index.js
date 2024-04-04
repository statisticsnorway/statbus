import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe, equals, isEmpty } from 'ramda'

import { getText } from '/helpers/locale'
import actionCreators from './actions.js'
import SearchStatUnit from './SearchStatUnit.jsx'

const { setQuery, ...actions } = actionCreators

const createFilterFromQuery = (query) => {
  const propsToConvert = ['sortBy', 'sortRule']
  return Object.entries(query)
    .map(([k, v]) => [k, propsToConvert.includes(k) ? Number(v) || undefined : v])
    .reduce((acc, [k, v]) => ({ ...acc, [k]: v }), {})
}

const hooks = {
  componentDidMount() {
    this.props.fetchLookup(5)
    if (!this.props.queryString) {
      this.props.clear()
      return
    }
    const newQuery = createFilterFromQuery(this.props.query)
    if (!equals(this.props.formData, newQuery)) {
      this.props.updateFilter(newQuery)
      this.props.fetchData(newQuery)
    }
    window.scrollTo(0, 0)
  },
  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  },
  componentDidUpdate(prevProps) {
    const prevQuery = prevProps.query
    const currentQuery = this.props.query

    if (
      (!isEmpty(prevQuery) && prevQuery.page !== currentQuery.page) ||
      prevQuery.pageSize !== currentQuery.pageSize
    ) {
      const newQuery = createFilterFromQuery(currentQuery)
      this.props.fetchData(newQuery)
    }
  },
}

const mapStateToProps = (state, props) => ({
  ...state.statUnits,
  query: props.location.query,
  queryString: props.location.search,
  localize: getText(state.locale),
  locale: state.locale,
  error: state.statUnits.error,
})

const mapDispatchToProps = (dispatch, props) => ({
  ...bindActionCreators(actions, dispatch),

  setQuery: (...params) => dispatch(setQuery(props.location.pathname)(...params)),
})

const enhance = pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))

export default enhance(SearchStatUnit)
