import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { lifecycle } from 'recompose'
import { pipe } from 'ramda'

import { getText } from '/helpers/locale'
import { fetchDataSourcesList, uploadFile } from '../actions.js'
import Upload from './Upload.jsx'

const mapStateToProps = (state, props) => ({
  query: props.location.query,
  dataSources: state.dataSources.dsList,
  localize: getText(state.locale),
})

const mapDispatchToProps = dispatch =>
  bindActionCreators({ fetchDataSourcesList, uploadFile }, dispatch)

const hooks = {
  componentDidMount() {
    this.props.fetchDataSourcesList()
  },
}

export default pipe(lifecycle(hooks), connect(mapStateToProps, mapDispatchToProps))(Upload)
