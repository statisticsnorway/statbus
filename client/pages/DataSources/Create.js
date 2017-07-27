import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import withOnMount from 'components/withOnMount'
import { getText } from 'helpers/locale'
import { create as createActions } from './actions'
import Form from './TemplateForm'

const { fetchColumns, ...actions } = createActions

export default connect(
  state => ({
    columns: state.dataSources.columns,
    localize: getText(state.locale),
  }),
  dispatch => ({
    ...bindActionCreators(actions, dispatch),
    onMount: () => dispatch(fetchColumns()),
  }),
)(withOnMount(Form))
