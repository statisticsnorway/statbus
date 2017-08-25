import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'
import { createSelector } from 'reselect'

import withSpinnerUnless from 'components/withSpinnerUnless'
import { getText } from 'helpers/locale'
import { actionCreators } from './actions'
import Edit from './Edit'

const hooks = {
  componentDidMount() {
    this.props.fetchMeta(this.props.type, this.props.regId)
  },
  componentWillReceiveProps(nextProps) {
    if (this.props.type !== nextProps.type || this.props.regId !== nextProps.regId) {
      nextProps.fetchMeta(nextProps.type, nextProps.regId)
    }
  },
}

const assert = props => props.properties !== undefined && props.dataAccess !== undefined

const createMapStateToProps = () => {
  const selector = createSelector(
    [
      state => state.editStatUnit,
      state => state.locale,
      (_, props) => props.params,
    ],
    (localState, locale, routeParams) => ({
      regId: Number(routeParams.id),
      type: Number(routeParams.type),
      properties: localState.properties,
      dataAccess: localState.dataAccess,
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
)(Edit)
