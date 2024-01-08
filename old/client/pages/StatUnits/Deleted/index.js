import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe, equals } from 'ramda'

import { getText } from '/helpers/locale'
import actionCreators from './actions.js'
import DeletedList from './DeletedList.jsx'

const { setQuery, ...actions } = actionCreators

const createFilterFromQuery = (query) => {
  const propsToConvert = ['sortBy', 'sortRule']
  return Object.entries(query)
    .map(([k, v]) => [k, propsToConvert.includes(k) ? Number(v) || undefined : v])
    .reduce((acc, [k, v]) => ({ ...acc, [k]: v }), {})
}

const hooks = {
  componentDidMount() {
    if (!this.props.queryString) {
      this.props.actions.clearSearchFormForDeleted()
      this.props.actions.fetchData(this.props.query)
      return
    }
    const newQuery = createFilterFromQuery(this.props.query)
    if (!equals(this.props.formData, newQuery)) {
      this.props.actions.updateFilter(newQuery)
      this.props.actions.fetchData(newQuery)
    }
    window.scrollTo(0, 0)
  },
  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchData(nextProps.query)
    }
  },
  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  },
}

const mapStateToProps = ({ deletedStatUnits, locale }, { location: { query, search } }) => ({
  ...deletedStatUnits,
  localize: getText(locale),
  queryString: search,
  query,
  locale,
})

const mapDispatchToProps = (dispatch, { location: { pathname } }) => ({
  actions: {
    ...bindActionCreators(actions, dispatch),
    setQuery: (...params) => dispatch(setQuery(pathname)(...params)),
  },
})

const enhance = pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))

export default enhance(DeletedList)
