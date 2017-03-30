import React from 'react'
import { Button, Icon, Table, Segment } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import { systemFunction as sF } from 'helpers/checkPermissions'
import RegionViewItem from './RegionsListItem'
import RegionEditItem from './RegionsListEditItem'
import styles from './styles'

const { func, number, bool, array } = React.PropTypes

class RegionsList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    fetchRegions: func.isRequired,
    regions: array.isRequired,
    fetching: bool.isRequired,
    toggleDeleteRegion: func.isRequired,
    editRegion: func.isRequired,
    editRow: number,
    editRegionRow: func.isRequired,
    addingRegion: bool.isRequired,
    addRegionEditor: func.isRequired,
    addRegion: func.isRequired,
  }
  static defaultProps = {
    editRow: undefined,
  }
  componentDidMount() {
    this.props.fetchRegions()
  }
  toggleAddRegionEditor = () => {
    this.props.addRegionEditor(!this.props.addingRegion)
  }
  handleEdit = (id) => {
    this.props.editRegionRow(id)
  }
  handleSave = (id, data) => {
    this.props.editRegion(id, data)
  }
  handleCancel = () => {
    this.props.editRegionRow(undefined)
  }
  handleAdd = (id, data) => {
    this.props.addRegion(data)
  }
  renderRow() {
    const { regions, toggleDeleteRegion, editRow, addingRegion } = this.props
    return (
      regions.map(r => (editRow !== r.id
      ? (
        <RegionViewItem
          key={r.id}
          data={r}
          onToggleDelete={toggleDeleteRegion}
          onEdit={this.handleEdit}
          readonly={editRow !== undefined || addingRegion}
        />
      )
      : (
        <RegionEditItem
          key={r.id}
          data={r}
          onSave={this.handleSave}
          onCancel={this.handleCancel}
        />
      )
    ))
    )
  }
  render() {
    const { localize, fetching, editRow, addingRegion } = this.props
    return (
      <div>
        <h2>{localize('Regions')}</h2>
        <Segment loading={fetching}>
          {sF('RegionsCreate') &&
            <Button
              positive
              onClick={this.toggleAddRegionEditor}
              disabled={addingRegion || editRow !== undefined}
              size="mini"
            >
              <Icon name="plus" /> {localize('RegionAdd')}
            </Button>}
          <Table selectable size="small" className={styles.wrap}>
            <Table.Header>
              <Table.Row>
                <Table.HeaderCell>{localize('RegionName')}</Table.HeaderCell>
                <Table.HeaderCell />
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {addingRegion &&
                <RegionEditItem
                  data={{ id: 0, name: '' }}
                  onSave={this.handleAdd}
                  onCancel={this.toggleAddRegionEditor}
                />}
              {this.renderRow()}
            </Table.Body>
          </Table>
        </Segment>
      </div>
    )
  }
}
export default wrapper(RegionsList)
