import React from 'react'
import { Table, Icon } from 'semantic-ui-react'

import { formatDateTime } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'

const reasons = {
  0: { icon: 'plus', name: 'ReasonCreate' },
  1: { icon: 'edit', name: 'ReasonEdit' },
  2: { icon: 'write', name: 'ReasonCorrect' },
  3: { icon: 'trash', name: 'ReasonDelete' },
  4: { icon: 'undo', name: 'ReasonUndelete' },
  null: { icon: 'help', name: 'ReasonUnknown' },
}

const { func, shape, number } = React.PropTypes
class HistoryList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    fetchHistory: func.isRequired,
    data: shape({ type: number.isRequired, regId: number.isRequired }).isRequired,
    history: shape({}).isRequired,
  }

  componentDidMount() {
    this
      .props
      .fetchHistory(this.props.data.type, this.props.data.regId)
  }
  renderRow() {
    const { history, localize } = this.props
    return (history.result.map(r => (
      <Table.Row key={r.regId}>
        <Table.Cell>
          {r.name}</Table.Cell>
        <Table.Cell>
          <Icon name={reasons[r.changeReason].icon} />
          {localize(reasons[r.changeReason].name)}
        </Table.Cell>
        <Table.Cell>
          {r.editComment}</Table.Cell>
        <Table.Cell>
          {formatDateTime(r.startPeriod)}</Table.Cell>
        <Table.Cell>
          {formatDateTime(r.endPeriod)}</Table.Cell>
      </Table.Row>
    )))
  }

  render() {
    const { history, localize } = this.props
    return (
      <Table celled>
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell>{localize('Account')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('ChangeReason')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Comment')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('StartPeriod')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('EndPeriod')}</Table.HeaderCell>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {history.result !== undefined && this.renderRow()}
        </Table.Body>
        <Table.Footer>
          <Table.Row>
            <Table.HeaderCell colSpan="5">
              {`${localize('Total')}: `}
              {history.totalCount !== undefined && history.totalCount}
            </Table.HeaderCell>
          </Table.Row>
        </Table.Footer>
      </Table>
    )
  }
}

export default wrapper(HistoryList)
