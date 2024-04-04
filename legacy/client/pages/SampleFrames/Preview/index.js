import { connect } from 'react-redux'
import { lifecycle } from 'recompose'
import * as R from 'ramda'

import withSpinnerUnless from '/components/withSpinnerUnless'
import getUid from '/helpers/getUid'
import { getText } from '/helpers/locale'
import { internalRequest } from '/helpers/request'
import { hasValue } from '/helpers/validation'
import List from './List.jsx'

const assert = props => props.error != null || props.list != null

const withUids = R.map(x => R.assoc('uid', getUid(), x))
const hooks = {
  componentDidMount() {
    internalRequest({
      url: `/api/sampleframes/${this.props.id}`,
      onSuccess: respInternal => this.setState({ sampleFrame: respInternal }),
      onFail: data => this.setState({ error: data.message }),
    })
    internalRequest({
      url: `/api/sampleframes/${this.props.id}/preview`,
      onSuccess: (resp) => {
        this.setState({ list: withUids(resp) })
        if (this.state.sampleFrame.fields.includes(4)) {
          internalRequest({
            url: '/api//lookup/9',
            onSuccess: (data) => {
              this.setState(s => ({
                ...s.list,
                list: s.list.map((x) => {
                  const temp = data.find(y => y.id === parseInt(x.unitStatusId, 10))
                  return {
                    ...x,
                    unitStatusId: hasValue(temp) ? temp.name : '',
                  }
                }),
              }))
            },
          })
        }
        if (this.state.sampleFrame.fields.includes(10)) {
          internalRequest({
            url: '/api//lookup/11',
            onSuccess: (data) => {
              this.setState(s => ({
                ...s.list,
                list: s.list.map((x) => {
                  const temp = data.find(y => y.id === parseInt(x.foreignParticipationId, 10))
                  return {
                    ...x,
                    foreignParticipationId: hasValue(temp) ? temp.name : '',
                  }
                }),
              }))
            },
          })
        }
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

const enhance = R.pipe(withSpinnerUnless(assert), lifecycle(hooks), connect(mapStateToProps))

export default enhance(List)
