import React from 'react'
import { Icon, Table } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import ActivityView from './View'
import ActivityEdit from './Edit'

const { array, func, string } = React.PropTypes

class ActivitiesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    data: array.isRequired,
    onChange: func.isRequired,
    labelKey: string.isRequired,
  }

  constructor(props) {
    super(props)
    this.state = {
      addRow: false,
      editRow: undefined,
    }
  }

  editHandler = (id) => {
    this.setState({
      editRow: id,
    })
  }

  deleteHandler = (id) => {
    this.changeHandler(this.props.data.filter(v => v.id !== id))
  }

  saveHandler = (data) => {
    this.changeHandler(this.props.data.map(v => v.id === data.id ? data : v))
    this.setState({ editRow: undefined })
  }

  editCancelHandler = () => {
    this.setState({ editRow: undefined })
  }

  addHandler = () => {
    this.setState({ addRow: true })
  }

  addSaveHandler = (data) => {
    this.changeHandler([data, ...this.props.data])
    this.setState({ addRow: false })
  }

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    const { onChange, name } = this.props
    onChange(this, { name, value })
  }

  renderRows() {
    const { data } = this.props
    const { addRow, editRow } = this.state
    return (
      data.map(v => (
        v.id !== editRow
          ? (
            <ActivityView
              key={v.id}
              data={v}
              onEdit={this.editHandler}
              onDelete={this.deleteHandler}
              readonly={editRow !== undefined || addRow}
            />
          )
          : (
            <ActivityEdit
              key={v.id}
              data={v}
              onSave={this.saveHandler}
              onCancel={this.editCancelHandler}
            />
          )
      ))
    )
  }

  render() {
    const { data, labelKey, localize } = this.props
    const { addRow, editRow } = this.state
    return (
      <div className="field">
        <label>{localize(labelKey)}</label>
        <Table size="small" compact>
          <Table.Header>
            <Table.Row>
              <Table.HeaderCell>{localize('StatUnitActivityRevX')}</Table.HeaderCell>
              <Table.HeaderCell>{localize('StatUnitActivityRevY')}</Table.HeaderCell>
              <Table.HeaderCell>{localize('StatUnitActivityYear')}</Table.HeaderCell>
              <Table.HeaderCell>{localize('StatUnitActivityType')}</Table.HeaderCell>
              <Table.HeaderCell>{localize('StatUnitActivityEmployeesNumber')}</Table.HeaderCell>
              <Table.HeaderCell>{localize('Turnover')}</Table.HeaderCell>
              <Table.HeaderCell textAlign="right">
                {editRow === undefined && addRow === false &&
                  <Icon name="add" color="green" onClick={this.addHandler} />
                }
              </Table.HeaderCell>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {addRow &&
              <ActivityEdit
                data={{ id: -1 }}
                onSave={this.addSaveHandler}
                onCancel={this.addCancelHandler}
              />
            }
            {data.length === 0 && !addRow
              ? (
                <Table.Row>
                  <Table.Cell textAlign="center" colSpan="7">{localize('TableNoRecords')}</Table.Cell>
                </Table.Row>
              )
              : this.renderRows()
            }
          </Table.Body>
        </Table>
      </div>
    )
  }
}

export default wrapper(ActivitiesList)
