import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

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

// TODO: use reselect
const mapStateToProps = (
  { createStatUnit: { dataAccess, properties, errors }, locale },
  { params: { type = 1 } },
) => ({
  type: Number(type),
  properties,
  dataAccess,
  errors,
  localize: getText(locale),
})

const mapDispatchToProps = dispatch => bindActionCreators(actionCreators, dispatch)

export default pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(
    mapStateToProps,
    mapDispatchToProps,
  ),
)(Create)
