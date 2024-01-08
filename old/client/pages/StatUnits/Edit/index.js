import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import { getText } from '/helpers/locale'
import { navigateBack } from '/helpers/actionCreators'
import { actionCreators } from './actions.js'
import Edit from './Edit.jsx'

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

const mapStateToProps = (state, props) => ({
  regId: Number(props.params.id),
  type: Number(props.params.type),
  localize: getText(state.locale),
  goBack: navigateBack,
  errors: state.editStatUnit.errors,
})

const { fetchMeta, submitStatUnit } = actionCreators
const mapDispatchToProps = dispatch => bindActionCreators({ fetchMeta, submitStatUnit }, dispatch)

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Edit)
