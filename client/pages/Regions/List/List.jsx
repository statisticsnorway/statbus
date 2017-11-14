import React from 'react'
import { func, number, bool, arrayOf, shape } from 'prop-types'
import { Button, Icon, Table, Segment } from 'semantic-ui-react'
import R from 'ramda'

import Paginate from 'components/Paginate'
import { checkSystemFunction as sF } from 'helpers/config'
import RegionViewItem from './RegionsListItem'
import RegionEditItem from './RegionsListEditItem'

class RegionsList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    fetchRegions: func.isRequired,
    regions: arrayOf(shape({})).isRequired,
    totalCount: number.isRequired,
    fetching: bool.isRequired,
    toggleDeleteRegion: func.isRequired,
    editRegion: func.isRequired,
    editRow: number,
    editRegionRow: func.isRequired,
    addingRegion: bool.isRequired,
    addRegionEditor: func.isRequired,
    addRegion: func.isRequired,
    query: shape({}).isRequired,
  }

  static defaultProps = {
    editRow: undefined,
  }

  componentDidMount() {
    this.props.fetchRegions(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.fetchRegions(nextProps.query)
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !R.equals(this.props, nextProps) ||
      !R.equals(this.state, nextState)
    )
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
    this.props.addRegion(data, this.props.query)
  }

  renderRows() {
    const { regions, toggleDeleteRegion, editRow, addingRegion, localize } = this.props
    return regions.map(r =>
      editRow !== r.id ? (
        <RegionViewItem
          key={r.id}
          data={r}
          onToggleDelete={toggleDeleteRegion}
          onEdit={this.handleEdit}
          readonly={editRow !== undefined || addingRegion}
          localize={localize}
        />
      ) : (
        <RegionEditItem
          key={r.id}
          data={r}
          onSave={this.handleSave}
          onCancel={this.handleCancel}
        />
      ))
  }

  render() {
    const { localize, fetching, editRow, addingRegion, totalCount } = this.props
    return (
      <div>
        <h2>{localize('Regions')}</h2>
        <Segment loading={fetching}>
          {sF('RegionsCreate') && (
            <Button
              positive
              onClick={this.toggleAddRegionEditor}
              disabled={addingRegion || editRow !== undefined}
              size="medium"
            >
              <Icon name="plus" /> {localize('RegionAdd')}
            </Button>
          )}
          <br />
          <br />
          <Paginate totalCount={Number(totalCount)}>
            <Table selectable size="small">
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell>{localize('RegionCode')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('RegionName')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('AdminstrativeCenter')}</Table.HeaderCell>
                  <Table.HeaderCell />
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {addingRegion && (
                  <RegionEditItem
                    data={{ id: 0, name: '', code: '', admCenter: '' }}
                    onSave={this.handleAdd}
                    onCancel={this.toggleAddRegionEditor}
                  />
                )}
                {this.renderRows()}
              </Table.Body>
            </Table>
          </Paginate>
        </Segment>
      </div>
    )
  }
}

export default RegionsList
