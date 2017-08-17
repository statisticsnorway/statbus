import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

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

// TODO: use reselect
const mapStateToProps = (
  { editStatUnit: { dataAccess, properties, errors }, locale },
  { params: { id, type } },
) => ({
  properties,
  dataAccess,
  errors,
  regId: id,
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
)(Edit)
