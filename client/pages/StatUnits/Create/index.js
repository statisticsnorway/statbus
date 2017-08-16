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

const assert = props => props.properties !== undefined && props.schema !== undefined

// TODO: use reselect
const mapStateToProps = (
  { createStatUnit: { dataAccess, properties, schema, errors }, locale },
  { params: { type } },
) => ({
  dataAccess,
  properties,
  schema,
  errors,
  type,
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
