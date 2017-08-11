import React from 'react'
import { shape, arrayOf, func, string, bool } from 'prop-types'
import { Icon, Table, Popup, Message } from 'semantic-ui-react'

import { getDate, formatDate } from 'helpers/dateHelper'
import ActivityView from './View'
import ActivityEdit from './Edit'

class ActivitiesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    value: arrayOf(shape({})),
    onChange: func,
    labelKey: string,
    readOnly: bool,
    errors: arrayOf(string),
  }

  static defaultProps = {
    value: [],
    readOnly: false,
    onChange: v => v,
    labelKey: '',
    errors: [],
  }

  state = {
    addRow: false,
    editRow: undefined,
    newRowId: -1,
  }

  editHandler = (id) => {
    this.setState({
      editRow: id,
    })
  }

  deleteHandler = (id) => {
    this.changeHandler(this.props.value.filter(v => v.id !== id))
  }

  saveHandler = (value) => {
    this.changeHandler(this.props.value.map(v => v.id === value.id ? value : v))
    this.setState({ editRow: undefined })
  }

  editCancelHandler = () => {
    this.setState({ editRow: undefined })
  }

  addHandler = () => {
    this.setState({ addRow: true })
  }

  addSaveHandler = (value) => {
    this.changeHandler([value, ...this.props.value])
    this.setState(s => ({
      addRow: false,
      newRowId: s.newRowId - 1,
    }))
  }

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    const { onChange, name } = this.props
    onChange({ name, value })
  }

  renderRows() {
    const { readOnly, value, localize } = this.props
    const { addRow, editRow } = this.state
    return (
      value.map(v => (
        v.id !== editRow
          ? (
            <ActivityView
              key={v.id}
              value={v}
              onEdit={this.editHandler}
              onDelete={this.deleteHandler}
              readOnly={readOnly}
              editMode={editRow !== undefined || addRow}
              localize={localize}
            />
          )
          : (
            <ActivityEdit
              key={v.id}
              value={v}
              onSave={this.saveHandler}
              onCancel={this.editCancelHandler}
              localize={localize}
            />
          )
      ))
    )
  }

  render() {
    const { readOnly, value, labelKey, localize, errors, name } = this.props
    const { addRow, editRow, newRowId } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && <label htmlFor={name}>{label}</label>}
        <Table size="small" id={name} compact celled>
          <Table.Header>
            <Table.Row>
              <Table.HeaderCell width={1}>{localize('StatUnitActivityRevXShort')}</Table.HeaderCell>
              <Table.HeaderCell width={5 + readOnly}>{localize('Activity')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('StatUnitActivityType')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('StatUnitActivityEmployeesNumber')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('Turnover')}</Table.HeaderCell>
              <Table.HeaderCell width={1} textAlign="center">{localize('Year')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('RegistrationDate')}</Table.HeaderCell>
              {!readOnly &&
                <Table.HeaderCell width={1} textAlign="right">
                  {editRow === undefined && addRow === false &&
                    <Popup
                      trigger={<Icon name="add" color="green" onClick={this.addHandler} />}
                      content={localize('ButtonAdd')}
                      size="mini"
                    />
                  }
                </Table.HeaderCell>
              }
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {addRow &&
              <ActivityEdit
                value={{
                  id: newRowId,
                  activityRevy: 0,
                  activityYear: new Date().getFullYear(),
                  activityType: 1,
                  employees: '',
                  turnover: '',
                  idDate: formatDate(getDate()),
                  activityRevxCategory: {
                    code: '',
                    name: '',
                  },
                }}
                onSave={this.addSaveHandler}
                onCancel={this.addCancelHandler}
                localize={localize}
              />
            }
            {value.length === 0 && !addRow
              ? (
                <Table.Row>
                  <Table.Cell textAlign="center" colSpan="7">{localize('TableNoRecords')}</Table.Cell>
                </Table.Row>
              )
              : this.renderRows()
            }
          </Table.Body>
        </Table>
        {errors.length !== 0 && <Message error title={label} list={errors.map(localize)} />}
      </div>
    )
  }
}

export default ActivitiesList
