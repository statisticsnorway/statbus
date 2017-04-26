import React from 'react'
import { Button, Icon, Table, Segment } from 'semantic-ui-react'
import R from 'ramda'

import Paginate from 'components/Paginate'
import { wrapper } from 'helpers/locale'
import { systemFunction as sF } from 'helpers/checkPermissions'
import SoateViewItem from './SoatesListItem'
import SoateEditItem from './SoatesListEditItem'

const { func, number, bool, arrayOf, shape } = React.PropTypes
class SoatesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    fetchSoates: func.isRequired,
    soates: arrayOf(shape({})).isRequired,
    totalCount: number.isRequired,
    fetching: bool.isRequired,
    toggleDeleteSoate: func.isRequired,
    editSoate: func.isRequired,
    editRow: number,
    editSoateRow: func.isRequired,
    addingSoate: bool.isRequired,
    addSoateEditor: func.isRequired,
    addSoate: func.isRequired,
    query: shape({}).isRequired,
  }

  static defaultProps = {
    editRow: undefined,
  }

  componentDidMount() {
    this.props.fetchSoates(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.fetchSoates(nextProps.query)
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  toggleAddSoateEditor = () => {
    this.props.addSoateEditor(!this.props.addingSoate)
  }

  handleEdit = (id) => {
    this.props.editSoateRow(id)
  }

  handleSave = (id, data) => {
    this.props.editSoate(id, data)
  }

  handleCancel = () => {
    this.props.editSoateRow(undefined)
  }

  handleAdd = (id, data) => {
    this.props.addSoate(data, this.props.query)
  }

  renderRows() {
    const {
      soates, toggleDeleteSoate, editRow, addingSoate, localize,
    } = this.props
    return soates.map(r => editRow !== r.id
      ? (
        <SoateViewItem
          key={r.id}
          data={r}
          onToggleDelete={toggleDeleteSoate}
          onEdit={this.handleEdit}
          readonly={editRow !== undefined || addingSoate}
          localize={localize}
        />
      ) : (
        <SoateEditItem
          key={r.id}
          data={r}
          onSave={this.handleSave}
          onCancel={this.handleCancel}
        />
      ))
  }

  render() {
    const { localize, fetching, editRow, addingSoate, totalCount } = this.props
    return (
      <div>
        <h2>{localize('Soates')}</h2>
        <Segment loading={fetching}>
          {sF('SoateCreate') &&
          <Button
            positive
            onClick={this.toggleAddSoateEditor}
            disabled={addingSoate || editRow !== undefined}
            size="medium"
          >
            <Icon name="plus" /> {localize('SoateAdd')}
          </Button>}
          <br />
          <br />
          <Paginate totalCount={Number(totalCount)}>
            <Table selectable size="small">
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell>{localize('SoateCode')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('SoateName')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('AdminstrativeCenter')}</Table.HeaderCell>
                  <Table.HeaderCell />
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {addingSoate &&
                <SoateEditItem
                  data={{ id: 0, name: '', code: '', admCenter: '' }}
                  onSave={this.handleAdd}
                  onCancel={this.toggleAddSoateEditor}
                />}
                {this.renderRows()}
              </Table.Body>
            </Table>
          </Paginate>
        </Segment>
      </div>
    )
  }
}

export default wrapper(SoatesList)
