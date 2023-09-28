import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import { getText } from '/client/helpers/locale'
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

const mapStateToProps = ({ createStatUnit: { isSubmitting }, locale }, { params: { type } }) => ({
  type: Number(type) || 1,
  isSubmitting,
  localize: getText(locale),
})

const { changeType, fetchMeta } = actionCreators
const mapDispatchToProps = dispatch => bindActionCreators({ changeType, fetchMeta }, dispatch)

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Create)
