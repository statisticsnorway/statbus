import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import withOnMount from 'components/withOnMount'
import { getText } from 'helpers/locale'
import { fetchDataSourcesList, uploadFile } from '../actions'
import Upload from './Upload'

export default connect(
  (state, props) => ({
    query: props.location.query,
    dataSources: state.dataSources.dsList,
    localize: getText(state.locale),
  }),
  dispatch => bindActionCreators(
    {
      onMount: fetchDataSourcesList,
      uploadFile,
    },
    dispatch,
  ),
)(withOnMount(Upload))
