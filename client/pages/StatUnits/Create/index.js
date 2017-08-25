import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'
import { createSelector } from 'reselect'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { actionCreators } from './actions'
import Create from './Create'

const hooks = {
  componentDidMount() {
    this.props.fetchMeta(this.props.type)
  },
  componentWillReceiveProps(nextProps) {
    if (this.props.type !== nextProps.type) {
      nextProps.fetchMeta(nextProps.type)
    }
  },
}

const assert = props => props.properties !== undefined && props.dataAccess !== undefined

const createMapStateToProps = () => {
  const selector = createSelector(
    [
      state => state.createStatUnit,
      state => state.locale,
      (_, props) => props.params.type,
    ],
    (localState, locale, type) => ({
      type: Number(type) || 1,
      properties: localState.properties,
      dataAccess: localState.dataAccess,
      isSubmitting: localState.isSubmitting,
      localize: getText(locale),
    }),
  )
  const mapStateToProps = (state, props) => selector(state, props)
  return mapStateToProps
}

const mapDispatchToProps = dispatch => bindActionCreators(actionCreators, dispatch)

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(
    createMapStateToProps,
    mapDispatchToProps,
  ),
)(Create)
