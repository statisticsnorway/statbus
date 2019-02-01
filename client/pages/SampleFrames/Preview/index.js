import { connect } from 'react-redux'
import { lifecycle } from 'recompose'
import R from 'ramda'

import withSpinnerUnless from 'components/withSpinnerUnless'
import getUid from 'helpers/getUid'
import { getText } from 'helpers/locale'
import { internalRequest } from 'helpers/request'
import List from './List'

const assert = props => props.list != null

const withUids = R.map(x => R.assoc('uid', getUid(), x))
const hooks = {
  componentDidMount() {
    internalRequest({
      url: '/api//lookup/9',
      onSuccess: (data) => {
        this.setState({ statuses: data })
        return internalRequest({
          url: `/api/sampleframes/${this.props.id}/preview`,
          onSuccess: (resp) => {
            this.setState({ list: withUids(resp) })
            this.setState(s => ({
              ...s.list,
              list: s.list.map(x => ({
                ...x,
                unitStatusId: this.state.statuses.find(v => v.id === parseInt(x.unitStatusId, 10))
                  .name,
              })),
            }))
            internalRequest({
              url: `/api/sampleframes/${this.props.id}`,
              onSuccess: respInternal => this.setState({ sampleFrame: respInternal }),
            })
          },
        })
      },
    })
  },
  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !R.equals(this.props, nextProps) ||
      !R.equals(this.state, nextState)
    )
  },
}

const mapStateToProps = (state, props) => ({
  localize: getText(state.locale),
  id: props.params.id,
})

const enhance = R.pipe(
  withSpinnerUnless(assert),
  lifecycle(hooks),
  connect(mapStateToProps),
)

export default enhance(List)
